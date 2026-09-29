//
//  ExhibitionExporter.swift
//  GoldenArchive
//
//  Data layer — renders an exhibition to a local PDF or PNG. The file is
//  only shared if the user chooses to share it.
//

import UIKit

final class ExhibitionExporter: ExhibitionExporting {

    private let media: MediaRepository

    init(media: MediaRepository) {
        self.media = media
    }

    private let navy = UIColor(red: 0x17 / 255, green: 0x2A / 255, blue: 0x46 / 255, alpha: 1)
    private let gold = UIColor(red: 0xF7 / 255, green: 0xC7 / 255, blue: 0x44 / 255, alpha: 1)
    private let ink = UIColor(red: 0x24 / 255, green: 0x1A / 255, blue: 0x10 / 255, alpha: 1)
    private let cream = UIColor(red: 0xFF / 255, green: 0xF8 / 255, blue: 0xE6 / 255, alpha: 1)
    private let muted = UIColor(red: 0x6E / 255, green: 0x5B / 255, blue: 0x45 / 255, alpha: 1)

    private func font(_ size: CGFloat, _ weight: UIFont.Weight, rounded: Bool = false) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        guard rounded, let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
        return UIFont(descriptor: descriptor, size: size)
    }

    private func image(for coin: Coin) -> UIImage? {
        guard let file = coin.primaryPhoto?.displayFile, let data = media.data(for: file) else { return nil }
        return UIImage(data: data)
    }

    private func attributes(for coin: Coin, units: MeasurementUnits) -> [(String, String)] {
        [
            ("Country", coin.country), ("Year", coin.year.map(YearText.display) ?? ""), ("Denomination", coin.denomination),
            ("Mint", coin.mint), ("Material", coin.material), ("Diameter", units.diameterText(coin.diameterMM) ?? ""),
            ("Weight", units.weightText(coin.weightGrams) ?? ""), ("Condition (own note)", coin.condition)
        ].filter { !$0.1.isBlank }
    }

    private func fileURL(_ exhibition: Exhibition, ext: String) -> URL {
        let safe = exhibition.title.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: "-")
        return FileManager.default.temporaryDirectory.appendingPathComponent("\(safe.isEmpty ? "Exhibition" : safe).\(ext)")
    }

    // MARK: PDF

    func exportPDF(_ exhibition: Exhibition, coins: [UUID: Coin], units: MeasurementUnits) throws -> URL {
        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        let margin: CGFloat = 48
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        let url = fileURL(exhibition, ext: "pdf")
        let items = exhibition.items.compactMap { item in coins[item.coinID].map { (item, $0) } }

        try renderer.writePDF(to: url) { context in
            // Title page
            context.beginPage()
            navy.setFill()
            UIRectFill(page)
            gold.setStroke()
            let frame = UIBezierPath(roundedRect: page.insetBy(dx: 24, dy: 24), cornerRadius: 18)
            frame.lineWidth = 4
            frame.stroke()
            let title = NSAttributedString(string: exhibition.title, attributes: [.font: font(34, .heavy, rounded: true), .foregroundColor: gold])
            title.draw(with: CGRect(x: margin, y: 300, width: page.width - margin * 2, height: 140), options: .usesLineFragmentOrigin, context: nil)
            if !exhibition.intro.isBlank {
                let intro = NSAttributedString(string: exhibition.intro, attributes: [.font: font(15, .regular), .foregroundColor: cream])
                intro.draw(with: CGRect(x: margin, y: 450, width: page.width - margin * 2, height: 240), options: .usesLineFragmentOrigin, context: nil)
            }
            let footer = NSAttributedString(
                string: "\(items.count) item\(items.count == 1 ? "" : "s") · Prepared \(DateFormatter.localizedString(from: Date(), dateStyle: .long, timeStyle: .none)) in Golden Archive\nA personal presentation of the owner's records. Not an appraisal or an offer for sale.",
                attributes: [.font: font(10, .regular), .foregroundColor: cream.withAlphaComponent(0.8)]
            )
            footer.draw(with: CGRect(x: margin, y: page.height - 110, width: page.width - margin * 2, height: 60), options: .usesLineFragmentOrigin, context: nil)

            // One item per page
            for (index, pair) in items.enumerated() {
                let (item, coin) = pair
                context.beginPage()
                cream.setFill()
                UIRectFill(page)
                var y: CGFloat = margin
                let counter = NSAttributedString(string: "\(index + 1) / \(items.count)", attributes: [.font: font(10, .semibold), .foregroundColor: muted])
                counter.draw(at: CGPoint(x: margin, y: y))
                y += 24
                if let photo = image(for: coin) {
                    let maxSide: CGFloat = 380
                    let scale = min(maxSide / photo.size.width, maxSide / photo.size.height)
                    let size = CGSize(width: photo.size.width * scale, height: photo.size.height * scale)
                    let rect = CGRect(x: (page.width - size.width) / 2, y: y, width: size.width, height: size.height)
                    photo.draw(in: rect)
                    y = rect.maxY + 24
                } else {
                    let note = NSAttributedString(string: "No photo recorded", attributes: [.font: font(12, .regular), .foregroundColor: muted])
                    note.draw(at: CGPoint(x: margin, y: y))
                    y += 30
                }
                let name = NSAttributedString(string: coin.displayName, attributes: [.font: font(24, .bold, rounded: true), .foregroundColor: ink])
                let nameRect = name.boundingRect(with: CGSize(width: page.width - margin * 2, height: 200), options: .usesLineFragmentOrigin, context: nil)
                name.draw(with: CGRect(x: margin, y: y, width: page.width - margin * 2, height: nameRect.height), options: .usesLineFragmentOrigin, context: nil)
                y += nameRect.height + 8
                if !item.caption.isBlank {
                    let caption = NSAttributedString(string: item.caption, attributes: [.font: font(13, .regular), .foregroundColor: ink])
                    let rect = caption.boundingRect(with: CGSize(width: page.width - margin * 2, height: 200), options: .usesLineFragmentOrigin, context: nil)
                    caption.draw(with: CGRect(x: margin, y: y, width: page.width - margin * 2, height: rect.height), options: .usesLineFragmentOrigin, context: nil)
                    y += rect.height + 14
                }
                gold.setFill()
                UIRectFill(CGRect(x: margin, y: y, width: 60, height: 3))
                y += 16
                for (label, value) in attributes(for: coin, units: units) {
                    let line = NSMutableAttributedString(string: "\(label): ", attributes: [.font: font(11, .semibold), .foregroundColor: muted])
                    line.append(NSAttributedString(string: value, attributes: [.font: font(11, .regular), .foregroundColor: ink]))
                    line.draw(with: CGRect(x: margin, y: y, width: page.width - margin * 2, height: 18), options: .usesLineFragmentOrigin, context: nil)
                    y += 18
                    if y > page.height - margin { break }
                }
            }
        }
        return url
    }

    // MARK: Image

    func exportImage(_ exhibition: Exhibition, coins: [UUID: Coin], units: MeasurementUnits) throws -> URL {
        let items = exhibition.items.compactMap { item in coins[item.coinID].map { (item, $0) } }
        let width: CGFloat = 1080
        let columns = 2
        let cardWidth: CGFloat = (width - 60 * 2 - 30) / CGFloat(columns)
        let cardHeight: CGFloat = cardWidth + 170
        let rows = Int(ceil(Double(items.count) / Double(columns)))
        let header: CGFloat = exhibition.intro.isBlank ? 260 : 360
        let height = header + CGFloat(rows) * (cardHeight + 30) + 140

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            navy.setFill()
            UIRectFill(CGRect(x: 0, y: 0, width: width, height: height))
            let title = NSAttributedString(string: exhibition.title, attributes: [.font: font(64, .heavy, rounded: true), .foregroundColor: gold])
            title.draw(with: CGRect(x: 60, y: 80, width: width - 120, height: 160), options: .usesLineFragmentOrigin, context: nil)
            if !exhibition.intro.isBlank {
                let intro = NSAttributedString(string: exhibition.intro, attributes: [.font: font(28, .regular), .foregroundColor: cream])
                intro.draw(with: CGRect(x: 60, y: 220, width: width - 120, height: 110), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
            }
            for (index, pair) in items.enumerated() {
                let (item, coin) = pair
                let col = index % columns, row = index / columns
                let x = 60 + CGFloat(col) * (cardWidth + 30)
                let y = header + CGFloat(row) * (cardHeight + 30)
                let card = UIBezierPath(roundedRect: CGRect(x: x, y: y, width: cardWidth, height: cardHeight), cornerRadius: 28)
                cream.setFill()
                card.fill()
                gold.setStroke()
                card.lineWidth = 6
                card.stroke()
                let photoRect = CGRect(x: x + 24, y: y + 24, width: cardWidth - 48, height: cardWidth - 48)
                if let photo = self.image(for: coin) {
                    let scale = min(photoRect.width / photo.size.width, photoRect.height / photo.size.height)
                    let size = CGSize(width: photo.size.width * scale, height: photo.size.height * scale)
                    photo.draw(in: CGRect(x: photoRect.midX - size.width / 2, y: photoRect.midY - size.height / 2, width: size.width, height: size.height))
                } else {
                    let empty = NSAttributedString(string: "No photo", attributes: [.font: font(24, .regular), .foregroundColor: muted])
                    empty.draw(at: CGPoint(x: photoRect.midX - 50, y: photoRect.midY - 14))
                }
                let name = NSAttributedString(string: coin.displayName, attributes: [.font: font(30, .bold, rounded: true), .foregroundColor: ink])
                name.draw(with: CGRect(x: x + 24, y: photoRect.maxY + 16, width: cardWidth - 48, height: 76), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
                let line = item.caption.isBlank ? coin.subtitle : item.caption
                let sub = NSAttributedString(string: line, attributes: [.font: font(22, .regular), .foregroundColor: muted])
                sub.draw(with: CGRect(x: x + 24, y: photoRect.maxY + 94, width: cardWidth - 48, height: 60), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
            }
            let footer = NSAttributedString(
                string: "A personal presentation made in Golden Archive. Not an appraisal or an offer for sale.",
                attributes: [.font: font(20, .regular), .foregroundColor: cream.withAlphaComponent(0.75)]
            )
            footer.draw(with: CGRect(x: 60, y: height - 90, width: width - 120, height: 40), options: .usesLineFragmentOrigin, context: nil)
            _ = context
        }
        guard let data = image.pngData() else { throw FileVaultError.writeFailed }
        let url = fileURL(exhibition, ext: "png")
        try data.write(to: url, options: .atomic)
        return url
    }
}
