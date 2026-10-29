import SwiftUI
import CoreImage.CIFilterBuiltins

/// 原生生成登录二维码（对应 Alger 前端渲染 qrurl）
struct QRCodeView: View {
    let content: String
    var body: some View {
        Image(uiImage: Self.qrImage(content))
            .interpolation(.none)
            .resizable()
            .scaledToFit()
    }
    static func qrImage(_ content: String) -> UIImage {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(content.utf8)
        filter.correctionLevel = "M"
        let ci = CIImage(color: .white).cropped(to: filter.outputImage!.extent)
            .composited(over: filter.outputImage!.transformed(by: CGAffineTransform(scaleX: 8, y: 8)))
        let ctx = CIContext()
        let cg = ctx.createCGImage(ci, from: ci.extent)!
        return UIImage(cgImage: cg)
    }
}
