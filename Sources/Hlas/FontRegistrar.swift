import CoreText
import Foundation

enum FontRegistrar {
    private static let names = [
        ("Satoshi-Regular", "otf"),
        ("Satoshi-Medium", "otf"),
        ("Satoshi-Bold", "otf"),
        ("KonectDemo-Regular", "ttf"),
    ]

    static func register() {
        for (name, ext) in names {
            guard let url = Bundle.main.url(forResource: name, withExtension: ext) else {
                Log.write("bundled font missing: \(name)")
                continue
            }
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                let code = error?.takeRetainedValue() as Error?
                Log.write("font registration failed: \(name), \(code?.localizedDescription ?? "unknown")")
            }
        }
    }
}
