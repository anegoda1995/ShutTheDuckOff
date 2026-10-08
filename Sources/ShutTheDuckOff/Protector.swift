import CoreAudio
import Foundation

/// While alive, every process playing to `device` (except `excluded`) is muted through a process tap and its
/// sound is played back to the same device by this process, which holds a 0.999 duck request. The audio server
/// does not duck a process that has a duck request of its own, so the replay stays at full volume while a call
/// app ducks "other audio". The price is about 0.1 s of extra latency for the tapped apps.
///
/// If this process dies, the tap goes away with it and the apps play directly again.
final class Protector {
    let device: AudioObjectID
    private(set) var excluded: Set<AudioObjectID>

    private var tapDescription: CATapDescription?
    private var tap = AudioObjectID(kAudioObjectUnknown)
    private var aggregate = AudioObjectID(kAudioObjectUnknown)
    private var ioProc: AudioDeviceIOProcID?
    /// Written by the I/O thread once the tap delivers sound.
    private let heardSound = UnsafeMutablePointer<Bool>.allocate(capacity: 1)

    struct Failure: Error, CustomStringConvertible {
        let step: String
        let status: OSStatus
        var description: String { "\(step) failed (\(status))" }
    }

    init(device: AudioObjectID, excluding: Set<AudioObjectID>) throws {
        let started = Date()
        self.device = device
        self.excluded = excluding
        heardSound.initialize(to: false)
        guard let deviceUID = CA.deviceUID(device) else { throw Failure(step: "device UID", status: -1) }

        let description = CATapDescription(excludingProcesses: Array(excluding), deviceUID: deviceUID, stream: 0)
        description.muteBehavior = .mutedWhenTapped
        description.isPrivate = true
        description.name = "ShutTheDuckOff"
        tapDescription = description
        var status = AudioHardwareCreateProcessTap(description, &tap)
        guard status == noErr else { throw Failure(step: "create tap", status: status) }

        let format: AudioStreamBasicDescription = CA.value(tap, kAudioTapPropertyFormat, AudioStreamBasicDescription())
        let tapBuffers = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0 ? Int(max(format.mChannelsPerFrame, 1)) : 1

        let config: [String: Any] = [
            kAudioAggregateDeviceNameKey: "ShutTheDuckOff",
            kAudioAggregateDeviceUIDKey: "shuttheduckoff." + UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: deviceUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: deviceUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: description.uuid.uuidString,
                                               kAudioSubTapDriftCompensationKey: true]],
        ]
        status = AudioHardwareCreateAggregateDevice(config as CFDictionary, &aggregate)
        guard status == noErr else { teardown(); throw Failure(step: "create aggregate", status: status) }

        let heard = heardSound
        status = AudioDeviceCreateIOProcIDWithBlock(&ioProc, aggregate, nil) { _, input, _, output, _ in
            Protector.copy(from: UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input)),
                           tapBuffers: tapBuffers, to: UnsafeMutableAudioBufferListPointer(output), heard: heard)
        }
        guard status == noErr else { teardown(); throw Failure(step: "create IOProc", status: status) }
        status = AudioDeviceStart(aggregate, ioProc)
        guard status == noErr else { teardown(); throw Failure(step: "start", status: status) }

        // The audio server mutes the tapped apps a few tens of milliseconds after I/O starts. A duck request made
        // before that would apply the call's full duck to them at once, and the tap would replay that, so wait
        // for the first sound (at most 0.25 s; with nothing playing there is nothing to replay).
        let ioStarted = Date()
        while !heardSound.pointee && Date().timeIntervalSince(ioStarted) < 0.25 { usleep(2000) }
        status = AudioDeviceDuck(device, 0.999, nil, 0)
        Log.info(String(format: "protecting %@ (%u), excluding %@, duck %d, ready in %.0f ms",
                        CA.deviceName(device), device, "\(excluding.sorted())", status, Date().timeIntervalSince(started) * 1000))
    }

    deinit { heardSound.deallocate() }

    /// Takes more processes out of the running tap. Changing only the process list does not interrupt the replay,
    /// unlike rebuilding the tap. Returns false if the tap refused the change.
    func exclude(_ more: Set<AudioObjectID>) -> Bool {
        guard let description = tapDescription else { return false }
        let alive = Set(CA.objects(CA.system, kAudioHardwarePropertyProcessObjectList))
        let updated = more.union(excluded.intersection(alive))
        description.processes = Array(updated)
        var address = CA.address(kAudioTapPropertyDescription)
        var value = description
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectSetPropertyData(tap, &address, 0, nil, UInt32(MemoryLayout<CATapDescription>.size), $0)
        }
        guard status == noErr else {
            description.processes = Array(excluded)
            Log.info("could not update the tap (\(status)), rebuilding it")
            return false
        }
        excluded = updated
        Log.info("now excluding \(updated.sorted())")
        return true
    }

    func stop() {
        _ = AudioDeviceDuck(device, 1.0, nil, 0)
        teardown()
        Log.info("stopped protecting \(CA.deviceName(device))")
    }

    private func teardown() {
        if let ioProc {
            AudioDeviceStop(aggregate, ioProc)
            AudioDeviceDestroyIOProcID(aggregate, ioProc)
            self.ioProc = nil
        }
        if aggregate != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregate)
            aggregate = AudioObjectID(kAudioObjectUnknown)
        }
        if tap != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tap)
            tap = AudioObjectID(kAudioObjectUnknown)
        }
    }

    /// Runs on the real-time I/O thread. The tap is the last `tapBuffers` input buffers, Float32. Output channel c
    /// takes tap channel c; if the device has more channels than the tap, the last tap channel is repeated.
    private static func copy(from input: UnsafeMutableAudioBufferListPointer, tapBuffers: Int,
                             to output: UnsafeMutableAudioBufferListPointer, heard: UnsafeMutablePointer<Bool>) {
        let first = input.count - tapBuffers
        var tapChannels = 0
        if first >= 0 { for i in first..<input.count { tapChannels += Int(input[i].mNumberChannels) } }

        if !heard.pointee, first >= 0 {
            for i in first..<input.count {
                guard let samples = input[i].mData?.assumingMemoryBound(to: Float.self) else { continue }
                for k in 0..<Int(input[i].mDataByteSize) / 4 where abs(samples[k]) > 1e-5 {
                    heard.pointee = true
                    break
                }
            }
        }

        var base = 0
        for buffer in output {
            let channels = Int(max(buffer.mNumberChannels, 1))
            defer { base += channels }
            guard let out = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
            let frames = Int(buffer.mDataByteSize) / (4 * channels)
            guard first >= 0, tapChannels > 0 else {
                memset(out, 0, Int(buffer.mDataByteSize))
                continue
            }
            for c in 0..<channels {
                var wanted = min(base + c, tapChannels - 1)
                var source = first
                while wanted >= Int(input[source].mNumberChannels) {
                    wanted -= Int(input[source].mNumberChannels)
                    source += 1
                }
                let src = input[source]
                let srcChannels = Int(max(src.mNumberChannels, 1))
                guard let samples = src.mData?.assumingMemoryBound(to: Float.self) else { continue }
                let count = min(frames, Int(src.mDataByteSize) / (4 * srcChannels))
                for f in 0..<count { out[f * channels + c] = samples[f * srcChannels + wanted] }
                if count < frames { for f in count..<frames { out[f * channels + c] = 0 } }
            }
        }
    }
}
