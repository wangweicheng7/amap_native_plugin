import Flutter
import UIKit

enum AmapPinRenderer {
  static func loadFlutterAssetImage(_ assetName: String) -> UIImage? {
    let assetKey = FlutterDartProject.lookupKey(forAsset: assetName)
    guard let path = Bundle.main.path(forResource: assetKey, ofType: nil) else {
      return nil
    }
    return UIImage(contentsOfFile: path)
  }

  static func customPinImage(_ style: CustomPinStyle) -> UIImage {
    let pinWidth = style.pinSize.width
    let pinHeight = style.pinSize.height
    let gap: CGFloat = 6
    let labelHeight: CGFloat = 32 * style.labelTextScaleFactor
    let horizontalPadding: CGFloat = 10 * style.labelTextScaleFactor
    let font = UIFont.boldSystemFont(ofSize: 14 * style.labelTextScaleFactor)
    let attributes: [NSAttributedString.Key: Any] = [
      .font: font,
      .foregroundColor: style.textColor
    ]
    let textSize = style.label.map { ($0 as NSString).size(withAttributes: attributes) } ?? .zero
    let labelWidth = style.label == nil ? 0 : ceil(textSize.width + horizontalPadding * 2)
    let size = CGSize(
      width: pinWidth + (style.label == nil ? 0 : gap + labelWidth),
      height: max(pinHeight, labelHeight)
    )

    return UIGraphicsImageRenderer(size: size).image { _ in
      if let pinImage = style.image {
        // Short marker images share the label's vertical center in the composed image.
        let pinTop = max(0, (size.height - pinHeight) / 2)
        pinImage.draw(
          in: CGRect(x: 0, y: pinTop, width: pinWidth, height: pinHeight)
        )
      } else {
        style.pinColor.setFill()
        let triangle = UIBezierPath()
        triangle.move(to: CGPoint(x: 8, y: 21))
        triangle.addLine(to: CGPoint(x: pinWidth / 2, y: pinHeight))
        triangle.addLine(to: CGPoint(x: 24, y: 21))
        triangle.close()
        triangle.fill()
        UIBezierPath(ovalIn: CGRect(x: 4, y: 2, width: 24, height: 24)).fill()
        UIColor.white.setFill()
        UIBezierPath(ovalIn: CGRect(x: 12, y: 10, width: 8, height: 8)).fill()
      }

      if let label = style.label {
        let labelRect = CGRect(
          x: pinWidth + gap,
          y: (size.height - labelHeight) / 2,
          width: labelWidth,
          height: labelHeight
        )
        style.backgroundColor.setFill()
        UIBezierPath(roundedRect: labelRect, cornerRadius: 8).fill()
        let textRect = CGRect(
          x: labelRect.minX + horizontalPadding,
          y: labelRect.midY - textSize.height / 2,
          width: textSize.width,
          height: textSize.height
        )
        (label as NSString).draw(in: textRect, withAttributes: attributes)
      }
    }
  }

  static func normalizedLabelTextScaleFactor(_ value: Any?) -> CGFloat {
    guard let number = value as? NSNumber else { return 1 }
    let scale = CGFloat(truncating: number)
    return scale.isFinite && scale > 0 ? min(scale, 4) : 1
  }

}

struct CustomPinStyle {
  let label: String?
  let image: UIImage?
  let pinSize: CGSize
  let pinColor: UIColor
  let textColor: UIColor
  let backgroundColor: UIColor
  let labelTextScaleFactor: CGFloat
}
