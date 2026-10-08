import docx
from docx import Document
from docx.shared import Inches, Pt, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.table import WD_TABLE_ALIGNMENT
from docx.oxml import OxmlElement, parse_xml
from docx.oxml.ns import nsdecls, qn

def set_cell_background(cell, fill_hex):
    tcPr = cell._tc.get_or_add_tcPr()
    shd = parse_xml(f'<w:shd {nsdecls("w")} w:fill="{fill_hex}"/>')
    tcPr.append(shd)

def set_cell_margins(cell, top=70, bottom=70, left=100, right=100):
    tcPr = cell._tc.get_or_add_tcPr()
    tcMar = OxmlElement('w:tcMar')
    for m, val in [('top', top), ('bottom', bottom), ('left', left), ('right', right)]:
        node = OxmlElement(f'w:{m}')
        node.set(qn('w:w'), str(val))
        node.set(qn('w:type'), 'dxa')
        tcMar.append(node)
    tcPr.append(tcMar)

def set_cell_borders(cell, color="CBD5E1", sz="4"):
    tcPr = cell._tc.get_or_add_tcPr()
    tcBorders = OxmlElement('w:tcBorders')
    for side in ['top', 'left', 'bottom', 'right']:
        b_val = OxmlElement(f'w:{side}')
        b_val.set(qn('w:val'), 'single')
        b_val.set(qn('w:sz'), sz)
        b_val.set(qn('w:space'), '0')
        b_val.set(qn('w:color'), color)
        tcBorders.append(b_val)
    tcPr.append(tcBorders)

def generate_docx():
    doc = Document()

    for section in doc.sections:
        section.top_margin = Inches(0.7)
        section.bottom_margin = Inches(0.7)
        section.left_margin = Inches(0.7)
        section.right_margin = Inches(0.7)

    NAVY = RGBColor(15, 23, 42)
    CYAN = RGBColor(2, 132, 199)
    DARK_GRAY = RGBColor(51, 65, 85)

    p_title = doc.add_paragraph()
    p_title.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p_title.paragraph_format.space_after = Pt(2)
    r_t = p_title.add_run("LA-VIE ENTERPRISE CONFERENCE & MEDIA ECOSYSTEM")
    r_t.font.name = "Arial"
    r_t.font.size = Pt(16)
    r_t.font.bold = True
    r_t.font.color.rgb = NAVY

    p_sub = doc.add_paragraph()
    p_sub.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p_sub.paragraph_format.space_after = Pt(10)
    r_s = p_sub.add_run("LIVEKIT ARCHITECTURE, ENTERPRISE COSTING, BANDWIDTH ECONOMICS & 20-YEAR SCALE BLUEPRINT")
    r_s.font.name = "Arial"
    r_s.font.size = Pt(10)
    r_s.font.bold = True
    r_s.font.color.rgb = CYAN

    memo_table = doc.add_table(rows=4, cols=2)
    memo_table.alignment = WD_TABLE_ALIGNMENT.CENTER
    memo_data = [
        ("PREPARED FOR:", "Executive Leadership & Enterprise Client Consultation"),
        ("AUTHOR / LEAD:", "Pastor Emmanuel Obinezu (Lead Software Engineer & Technology Director)"),
        ("DATE:", "September 2026"),
        ("SUBJECT:", "Definitive LiveKit Architecture, Cloud Billing Breakdown, 500-Participant Modeling & Self-Hosted Scale")
    ]
    for r_idx, (k, v) in enumerate(memo_data):
        c0 = memo_table.rows[r_idx].cells[0]
        c1 = memo_table.rows[r_idx].cells[1]
        c0.width = Inches(1.5)
        c1.width = Inches(5.6)
        c0.text = k
        c1.text = v
        set_cell_background(c0, "F1F5F9")
        set_cell_background(c1, "F8FAFC")
        set_cell_margins(c0, top=60, bottom=60, left=90, right=90)
        set_cell_margins(c1, top=60, bottom=60, left=90, right=90)
        set_cell_borders(c0, color="CBD5E1", sz="4")
        set_cell_borders(c1, color="CBD5E1", sz="4")
        
        p0 = c0.paragraphs[0].runs[0]
        p0.font.name = "Arial"
        p0.font.size = Pt(9)
        p0.font.bold = True
        p0.font.color.rgb = NAVY

        p1 = c1.paragraphs[0].runs[0]
        p1.font.name = "Arial"
        p1.font.size = Pt(9)
        p1.font.color.rgb = DARK_GRAY

    doc.add_paragraph().paragraph_format.space_after = Pt(8)

    def add_h1(text):
        h = doc.add_paragraph()
        h.paragraph_format.space_before = Pt(12)
        h.paragraph_format.space_after = Pt(3)
        h.paragraph_format.keep_with_next = True
        r = h.add_run(text)
        r.font.name = "Arial"
        r.font.size = Pt(12)
        r.font.bold = True
        r.font.color.rgb = NAVY

    def add_body(text, bold=""):
        p = doc.add_paragraph()
        p.paragraph_format.space_after = Pt(4)
        p.paragraph_format.line_spacing = 1.15
        if bold:
            rb = p.add_run(bold)
            rb.font.name = "Arial"
            rb.font.size = Pt(9)
            rb.font.bold = True
            rb.font.color.rgb = NAVY
        r = p.add_run(text)
        r.font.name = "Arial"
        r.font.size = Pt(9)
        r.font.color.rgb = DARK_GRAY

    def add_bullet(text, bold=""):
        p = doc.add_paragraph(style='List Bullet')
        p.paragraph_format.space_after = Pt(2.5)
        p.paragraph_format.line_spacing = 1.15
        if bold:
            rb = p.add_run(bold)
            rb.font.name = "Arial"
            rb.font.size = Pt(9)
            rb.font.bold = True
            rb.font.color.rgb = NAVY
        r = p.add_run(text)
        r.font.name = "Arial"
        r.font.size = Pt(9)
        r.font.color.rgb = DARK_GRAY

    # Section 1
    add_h1("1. Executive Summary & Problem Resolution")
    add_body("Many organizations encounter severe performance breakdowns when attempting large-scale meetings on conventional platforms like Microsoft Teams. Teams frequently suffers from video freezing, audio distortion, and app crashes in 300+ participant meetings due to its heavy Electron framework consuming 2–4 GB RAM and unoptimized background video subscriptions.")
    add_body("La-Vie was engineered to solve this through a dedicated Selective Forwarding Unit (SFU) architecture, audio silence suppression (Opus DTX), and viewport-aware subscriptions capping rendering to 9 active tiles. This ensures every participant requires only 1.0 to 1.5 Mbps of bandwidth, delivering rock-solid stability even for 500 to 1,000 attendees.")

    # Section 2
    add_h1("2. Plain-English Glossary of Video Infrastructure")
    add_bullet("Data downloaded from the media server to participants' screens/speakers. Uploading video is free; broadcasting video down to 500 viewers consumes metered egress.", "Egress Bandwidth (GB): ")
    add_bullet("The number of attendees multiplied by the duration of the meeting. 500 people in a 1-hour call consume 30,000 connection minutes.", "Connection Time (Minutes): ")
    add_bullet("An intelligent media routing server. Instead of 500 people connecting to each other (which crashes connections), each person connects to 1 central server that forwards streams efficiently.", "Selective Forwarding Unit (SFU): ")
    add_bullet("Automatically halts audio transmission during pauses in speech, cutting continuous audio bandwidth by 40–50% without quality loss.", "Opus Audio DTX: ")
    add_bullet("Limits video stream downloads to the 9 visible participants on screen. Off-screen attendees are paused, saving ~200 kbps per tile.", "Adaptive Viewport Subscription: ")

    # Section 3
    add_h1("3. LiveKit Cloud Plans & Payment Breakdown")
    add_body("LiveKit Cloud operates on a hybrid subscription-plus-metered-usage billing model:")
    add_bullet("Free forever, but has a HARD CAP of 50 GB monthly bandwidth and 100 concurrent participants. Once reached, all streams fail. (Cannot run 300+ meetings).", "Build Plan ($0/mo): ")
    add_bullet("Unlocks up to 1,000 concurrent participants per room, includes 250 GB of bandwidth, and 150,000 participant-minutes.", "Ship Plan ($50/mo): ")
    add_bullet("The Ship plan never cuts off. Overages are billed incrementally at $0.05 per extra GB and $0.0005 per extra participant-minute.", "Overage Mechanics: ")

    # Section 4
    add_h1("4. Scenario-Based Cost Modeling (The Math)")
    add_body("Based on La-Vie's verified benchmark (1 person in a 2-hour video meeting = ~1.08 GB data):")
    add_bullet("Consumes ~320 GB data and 36,000 minutes. 250 GB is covered by the $50 Ship plan; 70 GB overage = $3.50. Total cost = $53.50.", "Single 300-Person 2-Hour Meeting: ")
    add_bullet("Consumes ~1,280 GB data. Total monthly cost = $50 base + $51.50 overage = $101.50.", "Weekly 300-Person 2-Hour Meetings (4/mo): ")
    add_bullet("Consumes ~2,160 GB data. Total monthly cost = $50 base + $95.50 GB + $45 minutes = $190.50.", "Weekly 500-Person 2-Hour Meetings (4/mo): ")
    add_bullet("Consumes 5,400 GB (5.4 TB) and 600,000 minutes. Total LiveKit Cloud monthly cost = $50 base + $257.50 GB overage + $225 minute overage = $532.50.", "Weekly 500-Person 5-Hour Meetings (4/mo): ")

    # Section 5
    add_h1("5. The Scale Dilemma: LiveKit Cloud vs. Dedicated Self-Hosted Cluster")
    add_body("When you scale from 1 client to 10 enterprise clients, LiveKit Cloud's metered fees explode to ~$5,300/month, eroding your profits. In contrast, self-hosting LiveKit server on a dedicated cloud server (e.g. Hetzner) costs a flat $65–$85/month total:")
    add_bullet("20,000 GB (20 TB) to unlimited monthly bandwidth included for free.", "Zero Bandwidth Overages: ")
    add_bullet("There is no meter counting participant minutes ($0 per minute).", "Unlimited Connection Minutes: ")
    add_bullet("10 clients paying $350/mo = $3,500 revenue. Server cost = $75. Net monthly profit = $3,425 (97.8% margin).", "Financial Comparison: ")

    # Section 6
    add_h1("6. Recommended Client Packaging & Monetization")
    add_bullet("₦15,000 ($19.99)/month — Up to 100 participants, unlimited time, whiteboard, cloud recording.", "Pro Partner Tier: ")
    add_bullet("₦45,000 ($49.99)/month — Up to 300 participants, vMix/OBS ingest, YouTube/Facebook multi-streaming.", "Ministry & Broadcaster Tier: ")
    add_bullet("₦250,000 – ₦350,000 ($250 – $350)/month — Up to 500–1,000 participants, 5-hour meetings, multi-streaming, dedicated SLA.", "Enterprise Executive Tier (For this client): ")

    # Section 7
    add_h1("7. The 20-Year Architecture Roadmap")
    add_bullet("Upgrade LiveKit Cloud to the $50 Ship plan. Test the 300–500 person room immediately with zero code changes.", "Phase 1 (Immediate Pilot): ")
    add_bullet("Deploy open-source LiveKit server on a dedicated $65/mo Hetzner server with Redis and SSL on rtc.lifechangerstouch.org. Update .env once. Your Flutter apps and web client connect permanently with zero client updates.", "Phase 2 (Permanent Production): ")
    add_bullet("As you scale to 50+ clients, add more LiveKit nodes to the Redis cluster. LiveKit natively load-balances rooms across nodes.", "Phase 3 (Decade-Proof Clustering): ")

    docx_path = r"c:\xampp\htdocs\conferenceMe\La_Vie_LiveKit_Enterprise_Architecture_and_Costing_Report.docx"
    doc.save(docx_path)
    print(f"DOCX created at: {docx_path}")

if __name__ == "__main__":
    generate_docx()
