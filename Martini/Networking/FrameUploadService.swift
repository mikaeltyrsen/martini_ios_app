import Foundation

struct FrameUploadService {
    private let baseScriptsURL = "https://dev.staging.trymartini.com/scripts/"

    func uploadPhotoboard(
        imageData: Data,
        boardLabel: String,
        shootId: String,
        creativeId: String,
        frameId: String,
        bearerToken: String?
    ) async throws {
        guard let url = URL(string: "\(baseScriptsURL)frames/upload.php") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        if let bearerToken {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append(formField(name: "boardLabel", value: boardLabel, boundary: boundary))
        body.append(formField(name: "shootId", value: shootId, boundary: boundary))
        body.append(formField(name: "creativeId", value: creativeId, boundary: boundary))
        body.append(formField(name: "frameId", value: frameId, boundary: boundary))
        body.append(fileField(name: "file", filename: "photoboard.jpg", mimeType: "image/jpeg", data: imageData, boundary: boundary))
        body.append("--\(boundary)--\r\n".data(using: .utf8) ?? Data())
        request.httpBody = body

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    private func formField(name: String, value: String, boundary: String) -> Data {
        var field = "--\(boundary)\r\n"
        field += "Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n"
        field += "\(value)\r\n"
        return field.data(using: .utf8) ?? Data()
    }

    private func fileField(name: String, filename: String, mimeType: String, data: Data, boundary: String) -> Data {
        var field = "--\(boundary)\r\n"
        field += "Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n"
        field += "Content-Type: \(mimeType)\r\n\r\n"
        var fieldData = field.data(using: .utf8) ?? Data()
        fieldData.append(data)
        fieldData.append("\r\n".data(using: .utf8) ?? Data())
        return fieldData
    }
}
