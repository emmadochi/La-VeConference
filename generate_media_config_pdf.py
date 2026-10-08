import os
import sys
from reportlab.lib.pagesizes import letter
from reportlab.lib import colors
from reportlab.lib.units import inch
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.platypus import (
    SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, PageBreak, KeepTogether, HRFlowable, Preformatted
)
from reportlab.pdfgen import canvas

class NumberedCanvas(canvas.Canvas):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self._saved_page_states = []

    def showPage(self):
        self._saved_page_states.append(dict(self.__dict__))
        self._startPage()

    def save(self):
        num_pages = len(self._saved_page_states)
        for state in self._saved_page_states:
            self.__dict__.update(state)
            self.draw_page_decorations(num_pages)
            super().showPage()
        super().save()

    def draw_page_decorations(self, page_count):
        self.saveState()
        self.setFont("Helvetica", 8)
        self.setFillColor(colors.HexColor("#64748B"))
        
        if self._pageNumber > 1:
            # Running Header
            self.drawString(54, 750, "LA-VIE ENTERPRISE: MEDIA STORAGE, UPLOAD GUARDS & RETENTION ARCHITECTURE")
            self.setStrokeColor(colors.HexColor("#CBD5E1"))
            self.setLineWidth(0.5)
            self.line(54, 742, 558, 742)
            
            # Running Footer
            self.line(54, 48, 558, 48)
            self.drawString(54, 36, "Confidential - Life Changers Touch Multimedia - Engineering & Security Operations")
            page_text = f"Page {self._pageNumber} of {page_count}"
            self.drawRightString(558, 36, page_text)
        else:
            # First page bottom footer only
            self.setStrokeColor(colors.HexColor("#CBD5E1"))
            self.setLineWidth(0.5)
            self.line(54, 48, 558, 48)
            self.drawString(54, 36, "La-Vie Communications Platform | Media Storage Architecture & Upload Guards Specification")
            page_text = f"Page 1 of {page_count}"
            self.drawRightString(558, 36, page_text)
            
        self.restoreState()


def build_pdf():
    pdf_path = r"c:\xampp\htdocs\conferenceMe\La_Vie_Media_Storage_and_Upload_Guard_Specification.pdf"
    
    doc = SimpleDocTemplate(
        pdf_path,
        pagesize=letter,
        leftMargin=54,
        rightMargin=54,
        topMargin=54,
        bottomMargin=54
    )

    styles = getSampleStyleSheet()

    # Custom styles
    title_style = ParagraphStyle(
        'DocTitle',
        parent=styles['Normal'],
        fontName='Helvetica-Bold',
        fontSize=18,
        leading=22,
        textColor=colors.HexColor("#0F172A"),
        alignment=1, # Center
        spaceAfter=4
    )

    sub_style = ParagraphStyle(
        'DocSub',
        parent=styles['Normal'],
        fontName='Helvetica-Bold',
        fontSize=10,
        leading=14,
        textColor=colors.HexColor("#0284C7"), # Cyan / Ocean
        alignment=1,
        spaceAfter=14
    )

    h1_style = ParagraphStyle(
        'H1',
        parent=styles['Normal'],
        fontName='Helvetica-Bold',
        fontSize=12,
        leading=16,
        textColor=colors.HexColor("#0F172A"),
        spaceBefore=14,
        spaceAfter=6,
        keepWithNext=True
    )

    h2_style = ParagraphStyle(
        'H2',
        parent=styles['Normal'],
        fontName='Helvetica-Bold',
        fontSize=10,
        leading=14,
        textColor=colors.HexColor("#0369A1"),
        spaceBefore=10,
        spaceAfter=4,
        keepWithNext=True
    )

    body_style = ParagraphStyle(
        'Body',
        parent=styles['Normal'],
        fontName='Helvetica',
        fontSize=9,
        leading=13,
        textColor=colors.HexColor("#334155"),
        spaceAfter=5
    )

    bullet_style = ParagraphStyle(
        'Bullet',
        parent=styles['Normal'],
        fontName='Helvetica',
        fontSize=8.5,
        leading=12.5,
        textColor=colors.HexColor("#334155"),
        leftIndent=15,
        spaceAfter=3
    )

    table_header = ParagraphStyle(
        'TableHeader',
        parent=styles['Normal'],
        fontName='Helvetica-Bold',
        fontSize=8.5,
        leading=11,
        textColor=colors.white,
        alignment=0
    )

    table_cell = ParagraphStyle(
        'TableCell',
        parent=styles['Normal'],
        fontName='Helvetica',
        fontSize=8,
        leading=11,
        textColor=colors.HexColor("#1E293B")
    )

    table_cell_bold = ParagraphStyle(
        'TableCellBold',
        parent=styles['Normal'],
        fontName='Helvetica-Bold',
        fontSize=8,
        leading=11,
        textColor=colors.HexColor("#0F172A")
    )

    code_style = ParagraphStyle(
        'CodeStyle',
        parent=styles['Normal'],
        fontName='Courier',
        fontSize=7.5,
        leading=10,
        textColor=colors.HexColor("#0F172A")
    )

    elements = []

    # Title & Subtitle
    elements.append(Paragraph("LA-VIE ENTERPRISE COMMUNICATIONS PLATFORM", title_style))
    elements.append(Paragraph("MEDIA STORAGE ARCHITECTURE, UPLOAD GUARDS & RETENTION SPECIFICATION", sub_style))

    # Memo Box Table
    memo_data = [
        [Paragraph("<b>TO:</b>", table_cell_bold), Paragraph("Executive Leadership & Technical Infrastructure Board", table_cell)],
        [Paragraph("<b>FROM:</b>", table_cell_bold), Paragraph("Pastor Emmanuel Obinezu (Lead Software Engineer & Technical Project Lead)", table_cell)],
        [Paragraph("<b>MODULE:</b>", table_cell_bold), Paragraph("<code>media_config.py</code> & API Ingestion Guard System (FastAPI / WebRTC)", table_cell)],
        [Paragraph("<b>DATE:</b>", table_cell_bold), Paragraph("October 2026", table_cell)],
        [Paragraph("<b>SUBJECT:</b>", table_cell_bold), Paragraph("<b>Ephemeral Storage Lifecycle, Whitelisted MIME Types, Size Caps & Quota Architecture</b>", table_cell)],
    ]
    memo_table = Table(memo_data, colWidths=[1.1*inch, 5.9*inch])
    memo_table.setStyle(TableStyle([
        ('BACKGROUND', (0,0), (0,-1), colors.HexColor("#F1F5F9")),
        ('BACKGROUND', (1,0), (1,-1), colors.HexColor("#F8FAFC")),
        ('BOX', (0,0), (-1,-1), 0.5, colors.HexColor("#CBD5E1")),
        ('INNERGRID', (0,0), (-1,-1), 0.5, colors.HexColor("#E2E8F0")),
        ('TOPPADDING', (0,0), (-1,-1), 4),
        ('BOTTOMPADDING', (0,0), (-1,-1), 4),
        ('LEFTPADDING', (0,0), (-1,-1), 8),
        ('RIGHTPADDING', (0,0), (-1,-1), 8),
    ]))
    elements.append(memo_table)
    elements.append(Spacer(1, 10))

    # Section 1: Executive Overview
    elements.append(Paragraph("1. Executive Overview & Storage Philosophy", h1_style))
    elements.append(Paragraph(
        "In the La-Vie platform (incorporating La-Vie Enterprise Conference and LiChat Messenger), chat media and recordings operate on a <b>Local-First Ephemeral Transit Relay</b> model inspired by privacy-respecting architectures like WhatsApp and Signal. Unlike traditional cloud-bloated systems that store all historical attachments indefinitely on expensive cloud storage, La-Vie treats server disk and object storage as an ephemeral synchronization bridge.",
        body_style
    ))
    elements.append(Paragraph(
        "<b>Core Operational Principles:</b>",
        body_style
    ))
    elements.append(Paragraph("• <b>Local-First Device Persistence:</b> Client applications (Flutter Android/iOS and Web clients) download and cache voice notes, images, and documents directly to local hardware storage upon receipt.", bullet_style))
    elements.append(Paragraph("• <b>Automated Server Purge (TTL):</b> Server-side copies in <code>uploads/media/</code> expire after a configurable retention window (30 days default) and are purged by automated background cleanup workers.", bullet_style))
    elements.append(Paragraph("• <b>Zero Data Loss:</b> Because both sender and recipient retain permanent local sandboxed files, users maintain lifelong access to their conversations even after cloud copies expire.", bullet_style))
    elements.append(Paragraph("• <b>Cost Efficiency:</b> Reduces cloud storage and hosting disk usage by over 85–90%, avoiding runaway bandwidth and disk storage invoices.", bullet_style))
    elements.append(Paragraph("• <b>Profile Photo Permanence:</b> User avatar images are stored permanently in <code>uploads/profiles/</code> and are strictly exempt from TTL purging.", bullet_style))

    # Section 2: Configuration Matrix
    elements.append(Paragraph("2. Storage, Guard & Quota Configuration Parameters", h1_style))
    elements.append(Paragraph(
        "All parameters are defined in <code>media_config.py</code> and can be overridden dynamically at runtime using environment variables:",
        body_style
    ))

    config_table_data = [
        [
            Paragraph("Configuration Variable", table_header),
            Paragraph("Default Value", table_header),
            Paragraph("Calculated / Bytes", table_header),
            Paragraph("Operational Description & Enforcement", table_header)
        ],
        [
            Paragraph("<code>MEDIA_TTL_DAYS</code>", table_cell_bold),
            Paragraph("<code>30</code> days", table_cell),
            Paragraph("2,592,000 sec", table_cell),
            Paragraph("Chat attachments (images, video, audio, docs) auto-purged from server after 30 days.", table_cell)
        ],
        [
            Paragraph("<code>RECORDINGS_TTL_DAYS</code>", table_cell_bold),
            Paragraph("<code>7</code> days", table_cell),
            Paragraph("604,800 sec", table_cell),
            Paragraph("Temporary LiveKit room recording archives purged to prevent disk exhaustion.", table_cell)
        ],
        [
            Paragraph("<code>MAX_UPLOAD_MB</code>", table_cell_bold),
            Paragraph("<code>50</code> MB", table_cell),
            Paragraph("52,428,800 bytes", table_cell),
            Paragraph("Hard ceiling on any single file upload; streamed into memory/disk with immediate 413 cutoff.", table_cell)
        ],
        [
            Paragraph("<code>USER_QUOTA_MB</code>", table_cell_bold),
            Paragraph("<code>200</code> MB", table_cell),
            Paragraph("209,715,200 bytes", table_cell),
            Paragraph("Maximum total storage a single authenticated user can occupy in <code>uploads/media/</code>.", table_cell)
        ],
        [
            Paragraph("<code>MIN_FREE_DISK_MB</code>", table_cell_bold),
            Paragraph("<code>500</code> MB", table_cell),
            Paragraph("524,288,000 bytes", table_cell),
            Paragraph("Server safety buffer; uploads rejected (HTTP 507) if free disk falls below this threshold.", table_cell)
        ],
        [
            Paragraph("<code>MAX_UPLOADS_PER_MIN</code>", table_cell_bold),
            Paragraph("<code>10</code> / min", table_cell),
            Paragraph("Sliding 60s window", table_cell),
            Paragraph("Per-user rate limit defending against burst abuse, bot flooding, or script spam.", table_cell)
        ],
    ]

    cfg_table = Table(config_table_data, colWidths=[1.7*inch, 1.0*inch, 1.2*inch, 3.1*inch])
    cfg_table.setStyle(TableStyle([
        ('BACKGROUND', (0,0), (-1,0), colors.HexColor("#0F172A")),
        ('BOX', (0,0), (-1,-1), 0.5, colors.HexColor("#CBD5E1")),
        ('INNERGRID', (0,0), (-1,-1), 0.5, colors.HexColor("#E2E8F0")),
        ('TOPPADDING', (0,0), (-1,-1), 4),
        ('BOTTOMPADDING', (0,0), (-1,-1), 4),
        ('LEFTPADDING', (0,0), (-1,-1), 6),
        ('RIGHTPADDING', (0,0), (-1,-1), 6),
        ('ROWBACKGROUNDS', (0,1), (-1,-1), [colors.HexColor("#FFFFFF"), colors.HexColor("#F8FAFC")]),
    ]))
    elements.append(cfg_table)
    elements.append(Spacer(1, 10))

    # Section 3: MIME Types Whitelist
    elements.append(Paragraph("3. MIME Types & File Validation Security Whitelist", h1_style))
    elements.append(Paragraph(
        "To protect the server and client endpoints from malicious file execution (e.g., polyglots, web shells, and scripts), the ingestion pipeline enforces strict content-type verification:",
        body_style
    ))

    mime_table_data = [
        [
            Paragraph("Category", table_header),
            Paragraph("Whitelisted MIME Types (<code>ALLOWED_CHAT_MIME</code>)", table_header),
            Paragraph("Allowed Extensions", table_header)
        ],
        [
            Paragraph("<b>Images</b>", table_cell_bold),
            Paragraph("<code>image/jpeg</code>, <code>image/png</code>, <code>image/gif</code>, <code>image/webp</code>, <code>image/heic</code>, <code>image/heif</code>", table_cell),
            Paragraph(".jpg, .jpeg, .png, .gif, .webp, .heic, .heif", table_cell)
        ],
        [
            Paragraph("<b>Videos</b>", table_cell_bold),
            Paragraph("<code>video/mp4</code>, <code>video/quicktime</code>, <code>video/x-matroska</code>, <code>video/webm</code>, <code>video/3gpp</code>, <code>video/3gp</code>, <code>video/avi</code>, <code>video/mpeg</code>", table_cell),
            Paragraph(".mp4, .mov, .mkv, .webm, .3gp, .avi, .mpeg", table_cell)
        ],
        [
            Paragraph("<b>Audio & Voice</b>", table_cell_bold),
            Paragraph("<code>audio/mpeg</code>, <code>audio/ogg</code>, <code>audio/wav</code>, <code>audio/aac</code>, <code>audio/mp4</code>, <code>audio/webm</code>, <code>audio/x-m4a</code>, <code>audio/m4a</code>", table_cell),
            Paragraph(".mp3, .ogg, .wav, .aac, .m4a, .webm", table_cell)
        ],
        [
            Paragraph("<b>Documents</b>", table_cell_bold),
            Paragraph("<code>application/pdf</code> (Strict validation; binaries verify extension)", table_cell),
            Paragraph(".pdf", table_cell)
        ],
        [
            Paragraph("<b>Binary Streams</b>", table_cell_bold),
            Paragraph("<code>application/octet-stream</code> (Fallback validated against file extension whitelist)", table_cell),
            Paragraph("Verified extension map", table_cell)
        ],
        [
            Paragraph("<b>Profile Photos</b><br/>(<code>ALLOWED_PROFILE_MIME</code>)", table_cell_bold),
            Paragraph("<b>Image Only:</b> <code>image/jpeg</code>, <code>image/png</code>, <code>image/gif</code>, <code>image/webp</code>, <code>image/heic</code>, <code>image/heif</code>", table_cell),
            Paragraph(".jpg, .jpeg, .png, .gif, .webp (Strict image check)", table_cell)
        ],
    ]

    mime_table = Table(mime_table_data, colWidths=[1.5*inch, 3.8*inch, 1.7*inch])
    mime_table.setStyle(TableStyle([
        ('BACKGROUND', (0,0), (-1,0), colors.HexColor("#0F172A")),
        ('BOX', (0,0), (-1,-1), 0.5, colors.HexColor("#CBD5E1")),
        ('INNERGRID', (0,0), (-1,-1), 0.5, colors.HexColor("#E2E8F0")),
        ('TOPPADDING', (0,0), (-1,-1), 4),
        ('BOTTOMPADDING', (0,0), (-1,-1), 4),
        ('LEFTPADDING', (0,0), (-1,-1), 6),
        ('RIGHTPADDING', (0,0), (-1,-1), 6),
        ('ROWBACKGROUNDS', (0,1), (-1,-1), [colors.HexColor("#FFFFFF"), colors.HexColor("#F8FAFC")]),
    ]))
    elements.append(mime_table)
    elements.append(Spacer(1, 10))

    # Section 4: Security Ingestion Pipeline
    elements.append(Paragraph("4. Ingestion Security Pipeline & Attack Mitigation", h1_style))
    elements.append(Paragraph(
        "When an upload request reaches the FastAPI backend (e.g. <code>POST /api/chat/upload</code> or <code>POST /api/profile/upload</code>), it executes a multi-tiered defense sequence:",
        body_style
    ))
    elements.append(Paragraph("1. <b>Cryptographic Authentication:</b> Validates the Firebase ID Bearer Token (<code>_verify_upload_user</code>) to establish caller identity and UID.", bullet_style))
    elements.append(Paragraph("2. <b>Upload Rate Limit Guard:</b> Validates that the UID has not exceeded <code>MAX_UPLOADS_PER_MIN</code> (10/min) using an in-memory sliding window.", bullet_style))
    elements.append(Paragraph("3. <b>Disk Health Verification:</b> Queries <code>shutil.disk_usage('.')</code> to guarantee at least <code>MIN_FREE_DISK_BYTES</code> (500 MB) remains before receiving payloads.", bullet_style))
    elements.append(Paragraph("4. <b>Per-User Storage Quota:</b> Sums existing files attributed to the user in <code>uploads/media/</code> and rejects uploads if usage reaches <code>USER_QUOTA_BYTES</code> (200 MB).", bullet_style))
    elements.append(Paragraph("5. <b>Streaming Byte Guard:</b> Reads chunks in 64 KB buffers. If cumulative bytes exceed <code>MAX_UPLOAD_BYTES</code> (50 MB), the stream terminates immediately (HTTP 413) to prevent memory saturation.", bullet_style))
    elements.append(Paragraph("6. <b>Sanitized Storage:</b> Upload filenames are generated with sanitized UID timestamps (<code>clean_uid_timestamp.ext</code>) and written to isolated sandboxed folders.", bullet_style))

    # Section 5: Code Architecture
    elements.append(Paragraph("5. Production Python Source Reference (<code>media_config.py</code>)", h1_style))
    code_text = '''import os

# WhatsApp-style storage: chat media is a TEMPORARY RELAY on the server.
# Files are auto-purged after MEDIA_TTL_DAYS (default: 30 days).
MEDIA_TTL_DAYS = int(os.getenv("MEDIA_TTL_DAYS", "30"))
RECORDINGS_TTL_DAYS = int(os.getenv("RECORDINGS_TTL_DAYS", "7"))

# ── Upload guards ─────────────────────────────────────────────────────────────
MAX_UPLOAD_MB = int(os.getenv("MAX_UPLOAD_MB", "50"))
MAX_UPLOAD_BYTES = MAX_UPLOAD_MB * 1024 * 1024

ALLOWED_CHAT_MIME = {
    # Images
    "image/jpeg", "image/png", "image/gif", "image/webp", "image/heic", "image/heif",
    # Video
    "video/mp4", "video/quicktime", "video/x-matroska", "video/webm", "video/3gpp", "video/3gp", "video/avi", "video/mpeg",
    # Audio
    "audio/mpeg", "audio/ogg", "audio/wav", "audio/aac", "audio/mp4", "audio/webm", "audio/x-m4a", "audio/m4a",
    # Documents & Binary Fallback
    "application/pdf", "application/octet-stream",
}

ALLOWED_PROFILE_MIME = {
    "image/jpeg", "image/png", "image/gif", "image/webp", "image/heic", "image/heif",
}

# ── Per-user quota & disk guard ───────────────────────────────────────────────
USER_QUOTA_MB = int(os.getenv("USER_QUOTA_MB", "200"))
USER_QUOTA_BYTES = USER_QUOTA_MB * 1024 * 1024

MIN_FREE_DISK_MB = int(os.getenv("MIN_FREE_DISK_MB", "500"))
MIN_FREE_DISK_BYTES = MIN_FREE_DISK_MB * 1024 * 1024'''

    code_table = Table([[Preformatted(code_text, code_style)]], colWidths=[7.0*inch])
    code_table.setStyle(TableStyle([
        ('BACKGROUND', (0,0), (-1,-1), colors.HexColor("#F8FAFC")),
        ('BOX', (0,0), (-1,-1), 0.5, colors.HexColor("#CBD5E1")),
        ('TOPPADDING', (0,0), (-1,-1), 6),
        ('BOTTOMPADDING', (0,0), (-1,-1), 6),
        ('LEFTPADDING', (0,0), (-1,-1), 8),
        ('RIGHTPADDING', (0,0), (-1,-1), 8),
    ]))
    elements.append(code_table)

    # Build document
    doc.build(elements, canvasmaker=NumberedCanvas)
    print(f"Successfully generated PDF at: {pdf_path}")

if __name__ == "__main__":
    build_pdf()
