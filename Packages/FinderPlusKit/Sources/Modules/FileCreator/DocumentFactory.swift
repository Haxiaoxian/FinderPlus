import Foundation

/// Produces minimal but *valid* documents for formats that cannot be empty files.
/// Word, Excel, PowerPoint, Pages, Numbers, Keynote and Preview all open these.
public enum DocumentFactory {
    public static func wordDocument(date: Date = Date()) -> Data {
        var zip = ZipArchiveWriter(date: date)
        zip.add("[Content_Types].xml", contentTypes([
            ("/word/document.xml", "application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"),
        ]))
        zip.add("_rels/.rels", packageRelationships(main: "word/document.xml"))
        zip.add("docProps/core.xml", coreProperties(date: date))
        zip.add("docProps/app.xml", appProperties)
        zip.add("word/document.xml", """
        \(xmlHeader)<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body><w:p/>\
        <w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" \
        w:header="708" w:footer="708" w:gutter="0"/></w:sectPr></w:body></w:document>
        """)
        return zip.finalized()
    }

    public static func spreadsheet(date: Date = Date(), sheetName: String = "Sheet1") -> Data {
        var zip = ZipArchiveWriter(date: date)
        zip.add("[Content_Types].xml", contentTypes([
            ("/xl/workbook.xml", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"),
            ("/xl/worksheets/sheet1.xml", "application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"),
            ("/xl/styles.xml", "application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"),
        ]))
        zip.add("_rels/.rels", packageRelationships(main: "xl/workbook.xml"))
        zip.add("docProps/core.xml", coreProperties(date: date))
        zip.add("docProps/app.xml", appProperties)
        zip.add("xl/workbook.xml", """
        \(xmlHeader)<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" \
        xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>\
        <sheet name="\(escape(sheetName))" sheetId="1" r:id="rId1"/></sheets></workbook>
        """)
        zip.add("xl/_rels/workbook.xml.rels", relationships([
            ("rId1", "http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet", "worksheets/sheet1.xml"),
            ("rId2", "http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles", "styles.xml"),
        ]))
        zip.add("xl/worksheets/sheet1.xml", """
        \(xmlHeader)<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData/></worksheet>
        """)
        zip.add("xl/styles.xml", """
        \(xmlHeader)<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">\
        <fonts count="1"><font><sz val="11"/><name val="Calibri"/></font></fonts>\
        <fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>\
        <borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>\
        <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>\
        <cellXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/></cellXfs>\
        <cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>
        """)
        return zip.finalized()
    }

    public static func presentation(date: Date = Date()) -> Data {
        let namespaces = """
        xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" \
        xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" \
        xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"
        """
        let emptyTree = """
        <p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr><a:xfrm>\
        <a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr></p:spTree>
        """
        let relationshipBase = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"

        var zip = ZipArchiveWriter(date: date)
        zip.add("[Content_Types].xml", contentTypes([
            ("/ppt/presentation.xml", "application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"),
            ("/ppt/slides/slide1.xml", "application/vnd.openxmlformats-officedocument.presentationml.slide+xml"),
            ("/ppt/slideLayouts/slideLayout1.xml", "application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml"),
            ("/ppt/slideMasters/slideMaster1.xml", "application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml"),
            ("/ppt/theme/theme1.xml", "application/vnd.openxmlformats-officedocument.theme+xml"),
        ]))
        zip.add("_rels/.rels", packageRelationships(main: "ppt/presentation.xml"))
        zip.add("docProps/core.xml", coreProperties(date: date))
        zip.add("docProps/app.xml", appProperties)
        zip.add("ppt/presentation.xml", """
        \(xmlHeader)<p:presentation \(namespaces) saveSubsetFonts="1">\
        <p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="rId1"/></p:sldMasterIdLst>\
        <p:sldIdLst><p:sldId id="256" r:id="rId2"/></p:sldIdLst>\
        <p:sldSz cx="12192000" cy="6858000"/><p:notesSz cx="6858000" cy="9144000"/></p:presentation>
        """)
        zip.add("ppt/_rels/presentation.xml.rels", relationships([
            ("rId1", "\(relationshipBase)/slideMaster", "slideMasters/slideMaster1.xml"),
            ("rId2", "\(relationshipBase)/slide", "slides/slide1.xml"),
            ("rId3", "\(relationshipBase)/theme", "theme/theme1.xml"),
        ]))
        zip.add("ppt/slides/slide1.xml", """
        \(xmlHeader)<p:sld \(namespaces)><p:cSld>\(emptyTree)</p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sld>
        """)
        zip.add("ppt/slides/_rels/slide1.xml.rels", relationships([
            ("rId1", "\(relationshipBase)/slideLayout", "../slideLayouts/slideLayout1.xml"),
        ]))
        zip.add("ppt/slideLayouts/slideLayout1.xml", """
        \(xmlHeader)<p:sldLayout \(namespaces) type="blank" preserve="1"><p:cSld name="Blank">\(emptyTree)</p:cSld>\
        <p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sldLayout>
        """)
        zip.add("ppt/slideLayouts/_rels/slideLayout1.xml.rels", relationships([
            ("rId1", "\(relationshipBase)/slideMaster", "../slideMasters/slideMaster1.xml"),
        ]))
        zip.add("ppt/slideMasters/slideMaster1.xml", """
        \(xmlHeader)<p:sldMaster \(namespaces)><p:cSld><p:bg><p:bgRef idx="1001"><a:schemeClr val="bg1"/></p:bgRef></p:bg>\
        \(emptyTree)</p:cSld><p:clrMap bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" accent2="accent2" \
        accent3="accent3" accent4="accent4" accent5="accent5" accent6="accent6" hlink="hlink" folHlink="folHlink"/>\
        <p:sldLayoutIdLst><p:sldLayoutId id="2147483649" r:id="rId1"/></p:sldLayoutIdLst>\
        <p:txStyles><p:titleStyle/><p:bodyStyle/><p:otherStyle/></p:txStyles></p:sldMaster>
        """)
        zip.add("ppt/slideMasters/_rels/slideMaster1.xml.rels", relationships([
            ("rId1", "\(relationshipBase)/slideLayout", "../slideLayouts/slideLayout1.xml"),
            ("rId2", "\(relationshipBase)/theme", "../theme/theme1.xml"),
        ]))
        zip.add("ppt/theme/theme1.xml", theme)
        return zip.finalized()
    }

    /// A single blank page (A4 by default) PDF with a correct cross-reference table.
    public static func blankPDF(width: Int = 595, height: Int = 842) -> Data {
        let objects = [
            "<< /Type /Catalog /Pages 2 0 R >>",
            "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 \(width) \(height)] /Resources << >> /Contents 4 0 R >>",
            "<< /Length 0 >>\nstream\n\nendstream",
        ]
        var pdf = Data("%PDF-1.4\n%\u{E2}\u{E3}\u{CF}\u{D3}\n".utf8)
        var offsets: [Int] = []
        for (index, body) in objects.enumerated() {
            offsets.append(pdf.count)
            pdf.append(Data("\(index + 1) 0 obj\n\(body)\nendobj\n".utf8))
        }
        let xrefOffset = pdf.count
        var xref = "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
        for offset in offsets {
            xref += String(format: "%010d 00000 n \n", offset)
        }
        xref += "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(xrefOffset)\n%%EOF\n"
        pdf.append(Data(xref.utf8))
        return pdf
    }

    // MARK: Shared parts

    static let xmlHeader = #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>"# + "\n"

    static func contentTypes(_ overrides: [(String, String)]) -> String {
        let parts = overrides.map { #"<Override PartName="\#($0.0)" ContentType="\#($0.1)"/>"# }.joined()
        return xmlHeader + #"<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">"#
            + #"<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>"#
            + #"<Default Extension="xml" ContentType="application/xml"/>"#
            + parts
            + #"<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>"#
            + #"<Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>"#
            + "</Types>"
    }

    static func relationships(_ items: [(id: String, type: String, target: String)]) -> String {
        xmlHeader + #"<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">"#
            + items.map { #"<Relationship Id="\#($0.id)" Type="\#($0.type)" Target="\#($0.target)"/>"# }.joined()
            + "</Relationships>"
    }

    static func packageRelationships(main: String) -> String {
        relationships([
            ("rId1", "http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument", main),
            ("rId2", "http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties", "docProps/core.xml"),
            ("rId3", "http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties", "docProps/app.xml"),
        ])
    }

    static func coreProperties(date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let stamp = formatter.string(from: date)
        return xmlHeader + """
        <cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" \
        xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" \
        xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">\
        <dcterms:created xsi:type="dcterms:W3CDTF">\(stamp)</dcterms:created>\
        <dcterms:modified xsi:type="dcterms:W3CDTF">\(stamp)</dcterms:modified></cp:coreProperties>
        """
    }

    static let appProperties = xmlHeader + """
    <Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties"><Application>FinderPlus</Application></Properties>
    """

    static let theme = xmlHeader + """
    <a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" name="Office Theme"><a:themeElements>\
    <a:clrScheme name="Office"><a:dk1><a:sysClr val="windowText" lastClr="000000"/></a:dk1>\
    <a:lt1><a:sysClr val="window" lastClr="FFFFFF"/></a:lt1><a:dk2><a:srgbClr val="44546A"/></a:dk2>\
    <a:lt2><a:srgbClr val="E7E6E6"/></a:lt2><a:accent1><a:srgbClr val="4472C4"/></a:accent1>\
    <a:accent2><a:srgbClr val="ED7D31"/></a:accent2><a:accent3><a:srgbClr val="A5A5A5"/></a:accent3>\
    <a:accent4><a:srgbClr val="FFC000"/></a:accent4><a:accent5><a:srgbClr val="5B9BD5"/></a:accent5>\
    <a:accent6><a:srgbClr val="70AD47"/></a:accent6><a:hlink><a:srgbClr val="0563C1"/></a:hlink>\
    <a:folHlink><a:srgbClr val="954F72"/></a:folHlink></a:clrScheme>\
    <a:fontScheme name="Office"><a:majorFont><a:latin typeface="Calibri Light"/><a:ea typeface=""/><a:cs typeface=""/></a:majorFont>\
    <a:minorFont><a:latin typeface="Calibri"/><a:ea typeface=""/><a:cs typeface=""/></a:minorFont></a:fontScheme>\
    <a:fmtScheme name="Office"><a:fillStyleLst><a:solidFill><a:schemeClr val="phClr"/></a:solidFill>\
    <a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:fillStyleLst>\
    <a:lnStyleLst><a:ln w="6350"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln>\
    <a:ln w="12700"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln>\
    <a:ln w="19050"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln></a:lnStyleLst>\
    <a:effectStyleLst><a:effectStyle><a:effectLst/></a:effectStyle><a:effectStyle><a:effectLst/></a:effectStyle>\
    <a:effectStyle><a:effectLst/></a:effectStyle></a:effectStyleLst>\
    <a:bgFillStyleLst><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:solidFill><a:schemeClr val="phClr"/></a:solidFill>\
    <a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:bgFillStyleLst></a:fmtScheme></a:themeElements></a:theme>
    """

    static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
