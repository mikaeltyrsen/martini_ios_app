import Foundation
import UIKit
import Darwin

final class LocalJSONStore {
    static let shared = LocalJSONStore()

    private(set) var pack: PackPayload?
    private(set) var cameras: [DBCamera] = []
    private(set) var cameraModesByCameraId: [String: [DBCameraMode]] = [:]
    private(set) var lenses: [DBLens] = []
    private(set) var lensPacks: [PackLensPack] = []
    private(set) var lensPackItems: [PackLensPackItem] = []
    private(set) var appleDevices: [AppleDevice] = []
    private(set) var deviceProfiles: [String: DeviceCameraProfile] = [:]
    private(set) var profileRules: [DeviceCameraProfileRule] = []

    private let jsonResourceName = "martini_master_offline_db_v5"

    private init() {
        load()
    }

    func load() {
        guard let url = Bundle.main.url(forResource: jsonResourceName, withExtension: "json") else {
            print("❌ JSON pack missing: \(jsonResourceName).json")
            return
        }

        do {
            let data = try Data(contentsOf: url)
            let payload = try JSONDecoder().decode(PackPayload.self, from: data)
            pack = payload
            appleDevices = payload.appleDevices
            profileRules = payload.deviceCameraProfileRules
            deviceProfiles = Dictionary(uniqueKeysWithValues: payload.deviceCameraProfiles.map { ($0.profileId, $0) })
            cameras = payload.cameras.map { camera in
                DBCamera(
                    id: camera.id,
                    brand: camera.brand,
                    model: camera.model,
                    sensorType: camera.sensorType,
                    mount: camera.mount,
                    sensorWidthMm: nil,
                    sensorHeightMm: nil
                )
            }
            cameraModesByCameraId = Dictionary(grouping: payload.cameras.flatMap { camera in
                camera.modes.map { mode in
                    DBCameraMode(
                        id: mode.id,
                        cameraId: camera.id,
                        name: mode.name,
                        sensorWidthMm: mode.sensorWidthMm,
                        sensorHeightMm: mode.sensorHeightMm,
                        resolution: mode.resolution,
                        aspectRatio: mode.aspectRatio,
                        captureGate: mode.captureGate,
                        anamorphicPreviewSqueeze: mode.anamorphicPreviewSqueeze,
                        deliveryAspectRatio: mode.deliveryAspectRatio,
                        recommendedLensCoverage: mode.recommendedLensCoverage,
                        vignetteRisk: mode.vignetteRisk,
                        notes: mode.notes,
                        extraction: mode.extraction
                    )
                }
            }, by: { $0.cameraId })
            lenses = payload.lenses.map { lens in
                DBLens(
                    id: lens.id,
                    type: lens.type,
                    brand: lens.brand,
                    series: lens.series,
                    format: lens.format,
                    mounts: lens.mounts,
                    focalLengthMm: lens.focalLengthMm,
                    focalLengthMinMm: lens.focalLengthMmMin,
                    focalLengthMaxMm: lens.focalLengthMmMax,
                    maxTStop: lens.maxTStop,
                    squeeze: lens.squeeze
                )
            }
            lensPacks = payload.lensPacks
            lensPackItems = payload.lensPackItems
            print("✅ JSON pack loaded: \(cameras.count) cameras, \(lenses.count) lenses, \(payload.deviceCameraProfiles.count) device profiles")
        } catch {
            print("❌ JSON pack decode failed: \(error)")
        }
    }

    func fetchCameras() -> [DBCamera] {
        cameras
    }

    func fetchCameras(ids: [String]) -> [DBCamera] {
        guard !ids.isEmpty else { return [] }
        let idSet = Set(ids)
        return cameras.filter { idSet.contains($0.id) }
    }

    func fetchCameraModes(cameraId: String) -> [DBCameraMode] {
        cameraModesByCameraId[cameraId] ?? []
    }

    func fetchLenses() -> [DBLens] {
        lenses
    }

    func fetchLenses(ids: [String]) -> [DBLens] {
        guard !ids.isEmpty else { return [] }
        let idSet = Set(ids)
        return lenses.filter { idSet.contains($0.id) }
    }

    func fetchIPhoneCameras() -> [DBIPhoneCamera] {
        let deviceInfo = DeviceInfoResolver.currentDeviceInfo(knownDevices: appleDevices)
        guard let profile = matchProfile(for: deviceInfo) else {
            return []
        }
        return profile.modules.compactMap { module in
            guard let hfov = module.nativeHFOVDeg ?? approximateHFOV(equivFocalLengthMm: module.equivFocalLengthMm) else {
                return nil
            }
            let normalizedRole = normalizeRole(module.role)
            return DBIPhoneCamera(
                id: "\(profile.profileId)_\(normalizedRole)",
                iphoneModel: deviceInfo.model,
                cameraRole: normalizedRole,
                nativeHFOVDegrees: hfov,
                minZoom: module.minZoom,
                maxZoom: module.maxZoom
            )
        }
    }

    private func matchProfile(for deviceInfo: DeviceInfo) -> DeviceCameraProfile? {
        for rule in profileRules {
            if let family = rule.match.family, family.lowercased() != deviceInfo.family.lowercased() {
                continue
            }
            if let regex = rule.match.modelRegex, deviceInfo.model.range(of: regex, options: .regularExpression) == nil {
                continue
            }
            if let profile = deviceProfiles[rule.profileId] {
                return profile
            }
        }
        return nil
    }

    private func approximateHFOV(equivFocalLengthMm: Double?) -> Double? {
        guard let focalLength = equivFocalLengthMm, focalLength > 0 else { return nil }
        let hfovRadians = 2 * atan(36.0 / (2 * focalLength))
        return FOVMath.radiansToDegrees(hfovRadians)
    }

    private func normalizeRole(_ role: String) -> String {
        let lowered = role.lowercased()
        if lowered.contains("ultra") {
            return "ultra"
        }
        if lowered.contains("tele") {
            return "tele"
        }
        return "main"
    }
}

struct DeviceInfo {
    let hardwareId: String?
    let family: String
    let model: String
}

enum DeviceInfoResolver {
    static func currentDeviceInfo(knownDevices: [AppleDevice]) -> DeviceInfo {
        let hardwareId = currentHardwareIdentifier()
        let family = UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
        let model = knownDevices.first(where: { $0.hardwareId == hardwareId })?.model
            ?? UIDevice.current.model
        return DeviceInfo(hardwareId: hardwareId, family: family, model: model)
    }

    private static func currentHardwareIdentifier() -> String? {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        return String(cString: machine)
    }
}
