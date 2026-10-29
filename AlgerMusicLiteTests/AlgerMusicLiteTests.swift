import XCTest

final class InstallSmokeTest: XCTestCase {
    func testInstallToDevice() {
        // 该测试唯一目的：让 xcodebuild test 走 legacy 通道把宿主 App 安装到 iOS 16 真机
        XCTAssertTrue(true)
    }
}
