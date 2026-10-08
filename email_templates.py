# ==============================================================================
# LA-VIE RESPONSIVE BRANDED HTML EMAIL TEMPLATES
# Built with the official brand identity, logo, typography & glassmorphic styling.
# ==============================================================================

BRAND_LOGO_URL = "https://la-vie.lifechangerstouch.org/static/logoI.png"
APP_BASE_URL = "https://la-vie.lifechangerstouch.org"

def get_base_styles() -> str:
    return """
        @import url('https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&display=swap');
        body, table, td, a { -webkit-text-size-adjust: 100%; -ms-text-size-adjust: 100%; }
        table, td { mso-table-lspace: 0pt; mso-table-rspace: 0pt; }
        img { -ms-interpolation-mode: bicubic; border: 0; height: auto; line-height: 100%; outline: none; text-decoration: none; }
        table { border-collapse: collapse !important; }
        body { 
            height: 100% !important; 
            margin: 0 !important; 
            padding: 0 !important; 
            width: 100% !important; 
            background-color: #070B19; 
            font-family: 'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; 
            color: #C9D1D9;
        }
        @media only screen and (max-width: 600px) {
            .email-container { width: 100% !important; border-radius: 0 !important; }
            .content-padding { padding: 24px 20px !important; }
            .header-padding { padding: 24px 20px 16px 20px !important; }
            .btn-action { width: 100% !important; display: block !important; }
        }
    """

def get_header_html(badge_text: str = "OFFICIAL ANNOUNCEMENT", badge_color: str = "#00E5FF") -> str:
    return f"""
    <!-- BRAND HEADER -->
    <tr>
        <td align="center" class="header-padding" style="padding: 36px 40px 24px 40px; background: linear-gradient(180deg, rgba(92, 0, 255, 0.22) 0%, rgba(14, 19, 38, 0) 100%);">
            <table border="0" cellpadding="0" cellspacing="0">
                <tr>
                    <td align="center">
                        <table border="0" cellpadding="0" cellspacing="0">
                            <tr>
                                <td style="vertical-align: middle; padding-right: 12px;">
                                    <img src="{BRAND_LOGO_URL}" alt="La-Vie Logo" width="44" height="44" style="display: block; width: 44px; height: 44px; border-radius: 10px; border: 1.5px solid rgba(0, 229, 255, 0.5); box-shadow: 0 4px 15px rgba(0, 229, 255, 0.35);" />
                                </td>
                                <td style="vertical-align: middle; text-align: left;">
                                    <span style="font-size: 22px; font-weight: 800; color: #FFFFFF; letter-spacing: 2px; text-transform: uppercase; display: block; line-height: 1;">
                                        LA-VIE<span style="color: #00E5FF;">.</span>
                                    </span>
                                    <span style="font-size: 10px; font-weight: 600; color: #00E5FF; letter-spacing: 1.5px; text-transform: uppercase; display: block; margin-top: 4px;">
                                        PREMIUM BROADCAST &amp; CONFERENCE
                                    </span>
                                </td>
                            </tr>
                        </table>
                    </td>
                </tr>
                {f'''
                <tr>
                    <td align="center" style="padding-top: 20px;">
                        <div style="background: rgba(0, 229, 255, 0.1); border: 1px solid {badge_color}; color: {badge_color}; padding: 5px 14px; border-radius: 20px; font-size: 11px; font-weight: 700; display: inline-block; letter-spacing: 1px; text-transform: uppercase;">
                            {badge_text}
                        </div>
                    </td>
                </tr>
                ''' if badge_text else ''}
            </table>
        </td>
    </tr>
    """

def get_footer_html(sender_name: str = "La-Vie Conference") -> str:
    return f"""
    <!-- BRAND FOOTER -->
    <tr>
        <td align="center" style="padding: 28px 40px 32px 40px; background-color: #050814; border-top: 1px solid rgba(255, 255, 255, 0.06); color: #8B949E; font-size: 12px; line-height: 1.6;">
            <table border="0" cellpadding="0" cellspacing="0" style="margin-bottom: 16px;">
                <tr>
                    <td align="center" style="padding: 0 10px;">
                        <a href="{APP_BASE_URL}" target="_blank" style="color: #00E5FF; text-decoration: none; font-size: 12px; font-weight: 600;">Open Web App</a>
                    </td>
                    <td style="color: rgba(255,255,255,0.2);">&bull;</td>
                    <td align="center" style="padding: 0 10px;">
                        <a href="{APP_BASE_URL}/admin" target="_blank" style="color: #00E5FF; text-decoration: none; font-size: 12px; font-weight: 600;">Admin Center</a>
                    </td>
                    <td style="color: rgba(255,255,255,0.2);">&bull;</td>
                    <td align="center" style="padding: 0 10px;">
                        <a href="mailto:support@lifechangerstouch.org" style="color: #00E5FF; text-decoration: none; font-size: 12px; font-weight: 600;">Support</a>
                    </td>
                </tr>
            </table>
            <p style="margin: 0 0 6px 0; color: #8B949E;">
                Sent with &hearts; by <strong>{sender_name}</strong> &bull; Powered by Life Changers Touch International
            </p>
            <p style="margin: 0; color: #484F58; font-size: 11px;">
                You received this email because you are a registered user or event participant on La-Vie.
            </p>
        </td>
    </tr>
    """


def render_marketing_email(
    title: str,
    body: str,
    action_label: str = "Join Broadcast",
    action_url: str = APP_BASE_URL,
    image_url: str = "",
    sender_name: str = "La-Vie Conference"
) -> str:
    """Renders a promotional or community announcement email with the full brand identity."""
    
    formatted_body = body.replace("\n", "<br>")
    
    image_block = ""
    if image_url:
        image_block = f"""
        <tr>
            <td align="center" style="padding: 0 0 24px 0;">
                <img src="{image_url}" alt="Banner" width="520" style="display: block; width: 100%; max-width: 520px; border-radius: 12px; border: 1px solid rgba(0, 229, 255, 0.25); box-shadow: 0 6px 20px rgba(0,0,0,0.4);" />
            </td>
        </tr>
        """

    button_block = ""
    if action_url and action_label:
        button_block = f"""
        <tr>
            <td align="center" style="padding: 16px 0 28px 0;">
                <!--[if mso]>
                <v:roundrect xmlns:v="urn:schemas-microsoft-com:vml" xmlns:w="urn:schemas-microsoft-com:office:word" href="{action_url}" style="height:50px;v-text-anchor:middle;width:260px;" arcsize="25%" stroke="f" fillcolor="#00e5ff">
                <w:anchorlock/>
                <center style="color:#070b19;font-family:sans-serif;font-size:16px;font-weight:bold;">{action_label}</center>
                </v:roundrect>
                <![endif]-->
                <a href="{action_url}" target="_blank" class="btn-action" style="background: linear-gradient(135deg, #00E5FF 0%, #5C00FF 100%); background-color: #00E5FF; color: #070B19; display: inline-block; font-size: 15px; font-weight: 800; line-height: 50px; text-align: center; text-decoration: none; width: 260px; -webkit-text-size-adjust: none; border-radius: 25px; box-shadow: 0 6px 25px rgba(0, 229, 255, 0.45); text-transform: uppercase; letter-spacing: 1px;">
                    {action_label} &rarr;
                </a>
            </td>
        </tr>
        """

    return f"""<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>{title}</title>
    <style type="text/css">
        {get_base_styles()}
    </style>
</head>
<body style="margin: 0; padding: 0; background-color: #070B19;">
    <center style="width: 100%; background-color: #070B19; padding: 32px 0;">
        <table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%" class="email-container" style="max-width: 600px; margin: 0 auto; background-color: #0E1326; border-radius: 18px; border: 1px solid rgba(0, 229, 255, 0.25); overflow: hidden; box-shadow: 0 12px 36px rgba(0,0,0,0.65);">
            
            {get_header_html(badge_text="COMMUNITY BROADCAST", badge_color="#00E5FF")}

            <!-- MAIN CONTENT -->
            <tr>
                <td class="content-padding" style="padding: 10px 40px 24px 40px;">
                    <table border="0" cellpadding="0" cellspacing="0" width="100%">
                        {image_block}
                        <tr>
                            <td style="color: #FFFFFF; font-size: 24px; font-weight: 800; line-height: 1.35; text-align: center; padding-bottom: 18px; letter-spacing: -0.5px;">
                                {title}
                            </td>
                        </tr>
                        <tr>
                            <td style="color: #C9D1D9; font-size: 15px; line-height: 1.65; padding-bottom: 24px; text-align: left;">
                                {formatted_body}
                            </td>
                        </tr>
                        {button_block}
                    </table>
                </td>
            </tr>

            {get_footer_html(sender_name=sender_name)}

        </table>
    </center>
</body>
</html>
"""


def render_meeting_reminder_email(
    title: str,
    room_id: str,
    scheduled_time_str: str,
    host_name: str = "Host"
) -> str:
    """Renders a 15-minute countdown reminder email with high-contrast stage access."""
    room_url = f"{APP_BASE_URL}/?room={room_id}"

    return f"""<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Reminder: {title} is starting in 15 minutes!</title>
    <style type="text/css">
        {get_base_styles()}
    </style>
</head>
<body style="margin: 0; padding: 0; background-color: #070B19;">
    <center style="width: 100%; background-color: #070B19; padding: 32px 0;">
        <table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%" class="email-container" style="max-width: 600px; margin: 0 auto; background-color: #0E1326; border-radius: 18px; border: 1px solid rgba(0, 229, 255, 0.35); overflow: hidden; box-shadow: 0 12px 36px rgba(0,0,0,0.65);">
            
            {get_header_html(badge_text="🔴 STARTING IN 15 MINUTES", badge_color="#FF4365")}

            <!-- TITLE & DETAILS -->
            <tr>
                <td class="content-padding" align="center" style="padding: 16px 40px 28px 40px;">
                    <h1 style="color: #FFFFFF; font-size: 25px; font-weight: 800; margin: 0 0 12px 0; line-height: 1.3; letter-spacing: -0.5px;">
                        {title}
                    </h1>
                    <p style="color: #8B949E; font-size: 14px; margin: 0 0 24px 0;">
                        Hosted by <strong style="color: #FFFFFF;">{host_name}</strong> &bull; Starts at <span style="color: #00E5FF; font-weight: 600;">{scheduled_time_str}</span>
                    </p>

                    <!-- MEETING ROOM CARD -->
                    <div style="background: rgba(255, 255, 255, 0.03); border: 1px solid rgba(0, 229, 255, 0.2); border-radius: 14px; padding: 22px; margin-bottom: 28px; text-align: center;">
                        <span style="font-size: 12px; color: #8B949E; text-transform: uppercase; letter-spacing: 1px; display: block; margin-bottom: 6px;">
                            Conference Stage
                        </span>
                        <span style="font-size: 18px; font-weight: 700; color: #00E5FF; letter-spacing: 1px;">
                            {room_id}
                        </span>
                    </div>

                    <!-- JOIN BUTTON -->
                    <table border="0" cellpadding="0" cellspacing="0" style="margin: 0 auto;">
                        <tr>
                            <td align="center">
                                <!--[if mso]>
                                <v:roundrect xmlns:v="urn:schemas-microsoft-com:vml" xmlns:w="urn:schemas-microsoft-com:office:word" href="{room_url}" style="height:52px;v-text-anchor:middle;width:280px;" arcsize="25%" stroke="f" fillcolor="#00e5ff">
                                <w:anchorlock/>
                                <center style="color:#070b19;font-family:sans-serif;font-size:16px;font-weight:bold;">ENTER MEETING STAGE</center>
                                </v:roundrect>
                                <![endif]-->
                                <a href="{room_url}" target="_blank" class="btn-action" style="background: linear-gradient(135deg, #00E5FF 0%, #5C00FF 100%); background-color: #00E5FF; color: #070B19; display: inline-block; font-size: 16px; font-weight: 800; line-height: 52px; text-align: center; text-decoration: none; width: 280px; border-radius: 26px; box-shadow: 0 6px 25px rgba(0, 229, 255, 0.5); text-transform: uppercase; letter-spacing: 1px;">
                                    Enter Meeting Stage &rarr;
                                </a>
                            </td>
                        </tr>
                    </table>

                    <p style="color: #8B949E; font-size: 13px; margin: 24px 0 0 0;">
                        Or access via link: <a href="{room_url}" style="color: #00E5FF; text-decoration: underline; word-break: break-all;">{room_url}</a>
                    </p>
                </td>
            </tr>

            {get_footer_html(sender_name="La-Vie Meeting Coordinator")}

        </table>
    </center>
</body>
</html>
"""


def render_post_meeting_recap_email(
    room_id: str,
    title: str = "",
    notes_summary: str = "",
    recording_url: str = "",
    executive_summary: str = "",
    key_points: list = None,
    action_items: list = None,
) -> str:
    """Renders a branded post-meeting / post-service recap digest with AI summary, takeaways, replay & notes access."""
    
    display_title = title if title else f"Meeting: {room_id}"
    dashboard_url = APP_BASE_URL
    
    # Render Executive Summary block
    exec_summary_text = executive_summary or notes_summary or 'Session attendance, discussion takeaways, and resources have been saved to your dashboard.'
    
    # Render Key Points block
    key_points_html = ""
    if key_points and len(key_points) > 0:
        points_items = "".join([
            f'<li style="margin-bottom: 8px; color: #C9D1D9; font-size: 13.5px; line-height: 1.5;">{str(p).strip()}</li>'
            for p in key_points if str(p).strip()
        ])
        key_points_html = f"""
        <div style="background: rgba(0, 229, 255, 0.04); border: 1px solid rgba(0, 229, 255, 0.2); border-radius: 12px; padding: 18px 20px; margin-bottom: 20px;">
            <h4 style="color: #00E5FF; margin: 0 0 10px 0; font-size: 13px; font-weight: 700; text-transform: uppercase; letter-spacing: 1px;">
                💡 Key Discussion Takeaways
            </h4>
            <ul style="margin: 0; padding-left: 20px;">
                {points_items}
            </ul>
        </div>
        """

    # Render Action Items block
    action_items_html = ""
    if action_items and len(action_items) > 0:
        actions_list = "".join([
            f'<div style="display: flex; align-items: flex-start; margin-bottom: 8px; background: rgba(255,255,255,0.02); padding: 8px 12px; border-radius: 8px; border-left: 3px solid #00FFA3;"><span style="color: #00FFA3; font-weight: bold; margin-right: 8px;">✓</span><span style="color: #E6EDF3; font-size: 13px; line-height: 1.4;">{str(a).strip()}</span></div>'
            for a in action_items if str(a).strip()
        ])
        action_items_html = f"""
        <div style="background: rgba(0, 255, 163, 0.04); border: 1px solid rgba(0, 255, 163, 0.2); border-radius: 12px; padding: 18px 20px; margin-bottom: 20px;">
            <h4 style="color: #00FFA3; margin: 0 0 10px 0; font-size: 13px; font-weight: 700; text-transform: uppercase; letter-spacing: 1px;">
                🎯 Action Items &amp; Next Steps
            </h4>
            <div>
                {actions_list}
            </div>
        </div>
        """

    recording_block = ""
    if recording_url:
        recording_block = f"""
        <tr>
            <td align="center" style="padding: 10px 0 20px 0;">
                <a href="{recording_url}" target="_blank" style="background: rgba(92, 0, 255, 0.2); border: 1.5px solid #5C00FF; color: #FFFFFF; display: inline-block; font-size: 14px; font-weight: 700; padding: 12px 28px; border-radius: 12px; text-decoration: none; box-shadow: 0 4px 15px rgba(92, 0, 255, 0.3);">
                    🎥 Watch Meeting Recording &bull; Replay
                </a>
            </td>
        </tr>
        """

    return f"""<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>AI Meeting Summary &amp; Recap: {display_title}</title>
    <style type="text/css">
        {get_base_styles()}
    </style>
</head>
<body style="margin: 0; padding: 0; background-color: #070B19;">
    <center style="width: 100%; background-color: #070B19; padding: 32px 0;">
        <table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%" class="email-container" style="max-width: 600px; margin: 0 auto; background-color: #0E1326; border-radius: 18px; border: 1px solid rgba(155, 85, 255, 0.35); overflow: hidden; box-shadow: 0 12px 36px rgba(0,0,0,0.65);">
            
            {get_header_html(badge_text="✨ AI MEETING SUMMARY &bull; RECAP", badge_color="#00E5FF")}

            <!-- TITLE & RECAP -->
            <tr>
                <td class="content-padding" style="padding: 16px 40px 28px 40px; color: #C9D1D9; font-size: 15px; line-height: 1.65;">
                    <h2 style="color: #FFFFFF; font-size: 24px; font-weight: 800; margin: 0 0 8px 0; text-align: center; letter-spacing: -0.5px;">
                        {display_title}
                    </h2>
                    <p style="text-align: center; color: #8B949E; margin-bottom: 24px; font-size: 13.5px;">
                        Thank you for attending today on La-Vie. Your automated AI meeting transcript, key takeaways, and action items are compiled below.
                    </p>

                    <!-- EXECUTIVE SUMMARY BOX -->
                    <div style="background: rgba(255, 255, 255, 0.03); border: 1px solid rgba(255, 255, 255, 0.08); border-left: 4px solid #00E5FF; border-radius: 10px; padding: 20px; margin-bottom: 20px;">
                        <h4 style="color: #00E5FF; margin: 0 0 8px 0; font-size: 13px; text-transform: uppercase; letter-spacing: 1px;">
                            📝 Executive Summary
                        </h4>
                        <p style="color: #C9D1D9; font-size: 14px; line-height: 1.6; margin: 0;">
                            {exec_summary_text}
                        </p>
                    </div>

                    {key_points_html}
                    {action_items_html}

                    <table border="0" cellpadding="0" cellspacing="0" width="100%">
                        {recording_block}
                        <tr>
                            <td align="center" style="padding-top: 10px;">
                                <a href="{dashboard_url}" target="_blank" class="btn-action" style="background: linear-gradient(135deg, #00E5FF 0%, #5C00FF 100%); color: #070B19; display: inline-block; font-size: 15px; font-weight: 800; line-height: 48px; text-align: center; text-decoration: none; width: 240px; border-radius: 24px; box-shadow: 0 6px 20px rgba(0, 229, 255, 0.45); text-transform: uppercase; letter-spacing: 0.5px;">
                                    Open Dashboard &rarr;
                                </a>
                            </td>
                        </tr>
                    </table>
                </td>
            </tr>

            {get_footer_html(sender_name="La-Vie AI Meeting Assistant")}

        </table>
    </center>
</body>
</html>
"""


def render_ticket_confirmation_email(
    ticket_id: str,
    user_name: str,
    subject: str,
    category: str = "General"
) -> str:
    """Renders a confirmation receipt email when a user creates a new support ticket."""
    display_name = user_name if user_name else "Valued Member"
    category_display = category.replace("_", " ").title()

    return f"""<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Support Request Received: #{ticket_id}</title>
    <style type="text/css">
        {get_base_styles()}
    </style>
</head>
<body style="margin: 0; padding: 0; background-color: #070B19;">
    <center style="width: 100%; background-color: #070B19; padding: 32px 0;">
        <table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%" class="email-container" style="max-width: 600px; margin: 0 auto; background-color: #0E1326; border-radius: 18px; border: 1px solid rgba(0, 229, 255, 0.3); overflow: hidden; box-shadow: 0 12px 36px rgba(0,0,0,0.65);">
            
            {get_header_html(badge_text=f"TICKET #{ticket_id} &bull; RECEIVED", badge_color="#00E5FF")}

            <!-- CONTENT -->
            <tr>
                <td class="content-padding" style="padding: 16px 40px 28px 40px; color: #C9D1D9; font-size: 15px; line-height: 1.65;">
                    <h2 style="color: #FFFFFF; font-size: 23px; font-weight: 800; margin: 0 0 12px 0; text-align: center; letter-spacing: -0.5px;">
                        We've Received Your Request!
                    </h2>
                    <p style="text-align: center; color: #8B949E; margin-bottom: 24px;">
                        Hello <strong>{display_name}</strong>, our support team has received your ticket and is currently investigating.
                    </p>

                    <!-- TICKET SUMMARY CARD -->
                    <div style="background: rgba(255, 255, 255, 0.03); border: 1px solid rgba(0, 229, 255, 0.2); border-radius: 12px; padding: 20px; margin-bottom: 24px;">
                        <table border="0" cellpadding="0" cellspacing="0" width="100%">
                            <tr>
                                <td style="padding-bottom: 8px; color: #8B949E; font-size: 13px;">Ticket ID:</td>
                                <td style="padding-bottom: 8px; color: #00E5FF; font-weight: 700; font-size: 14px; text-align: right;">#{ticket_id}</td>
                            </tr>
                            <tr>
                                <td style="padding-bottom: 8px; color: #8B949E; font-size: 13px;">Subject:</td>
                                <td style="padding-bottom: 8px; color: #FFFFFF; font-weight: 600; font-size: 14px; text-align: right;">{subject}</td>
                            </tr>
                            <tr>
                                <td style="color: #8B949E; font-size: 13px;">Category:</td>
                                <td style="color: #00E5FF; font-weight: 600; font-size: 13px; text-align: right;">{category_display}</td>
                            </tr>
                        </table>
                    </div>

                    <p style="color: #8B949E; font-size: 14px; line-height: 1.6; text-align: center; margin: 0;">
                        You will receive an email and in-app alert as soon as an agent replies. You can also view status anytime in your dashboard.
                    </p>
                </td>
            </tr>

            {get_footer_html(sender_name="La-Vie Support Center")}

        </table>
    </center>
</body>
</html>
"""


def render_support_reply_email(
    ticket_id: str,
    user_name: str,
    subject: str,
    reply_message: str,
    status: str = "in_progress",
    agent_name: str = "La-Vie Support Team"
) -> str:
    """Renders a branded notification email when an administrator replies to a support ticket."""
    display_name = user_name if user_name else "Valued Member"
    formatted_reply = reply_message.replace("\n", "<br>")
    
    status_badge = "🔵 IN PROGRESS"
    status_color = "#00E5FF"
    if status == "resolved":
        status_badge = "🟢 RESOLVED"
        status_color = "#00FFA3"

    return f"""<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>New Reply on Ticket #{ticket_id}: {subject}</title>
    <style type="text/css">
        {get_base_styles()}
    </style>
</head>
<body style="margin: 0; padding: 0; background-color: #070B19;">
    <center style="width: 100%; background-color: #070B19; padding: 32px 0;">
        <table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%" class="email-container" style="max-width: 600px; margin: 0 auto; background-color: #0E1326; border-radius: 18px; border: 1px solid rgba(0, 229, 255, 0.35); overflow: hidden; box-shadow: 0 12px 36px rgba(0,0,0,0.65);">
            
            {get_header_html(badge_text=f"TICKET #{ticket_id} &bull; {status_badge}", badge_color=status_color)}

            <!-- TITLE & DETAILS -->
            <tr>
                <td class="content-padding" style="padding: 16px 40px 28px 40px; color: #C9D1D9; font-size: 15px; line-height: 1.65;">
                    <h2 style="color: #FFFFFF; font-size: 23px; font-weight: 800; margin: 0 0 8px 0; text-align: center; letter-spacing: -0.5px;">
                        Update on Your Support Request
                    </h2>
                    <p style="text-align: center; color: #8B949E; margin-bottom: 24px; font-size: 14px;">
                        Regarding: <strong style="color: #FFFFFF;">{subject}</strong>
                    </p>

                    <!-- AGENT RESPONSE BOX -->
                    <div style="background: rgba(0, 229, 255, 0.04); border: 1px solid rgba(0, 229, 255, 0.25); border-left: 4px solid #00E5FF; border-radius: 12px; padding: 22px; margin-bottom: 26px; box-shadow: 0 6px 20px rgba(0,0,0,0.3);">
                        <div style="display: flex; align-items: center; margin-bottom: 12px;">
                            <span style="color: #00E5FF; font-weight: 700; font-size: 14px; text-transform: uppercase; letter-spacing: 0.5px;">
                                {agent_name}
                            </span>
                            <span style="color: #8B949E; font-size: 12px; margin-left: auto;">Official Response</span>
                        </div>
                        <div style="color: #FFFFFF; font-size: 15px; line-height: 1.65;">
                            {formatted_reply}
                        </div>
                    </div>

                    <!-- CTA BUTTON -->
                    <table border="0" cellpadding="0" cellspacing="0" width="100%">
                        <tr>
                            <td align="center" style="padding-bottom: 12px;">
                                <a href="{APP_BASE_URL}" target="_blank" class="btn-action" style="background: linear-gradient(135deg, #00E5FF 0%, #5C00FF 100%); color: #070B19; display: inline-block; font-size: 15px; font-weight: 800; line-height: 48px; text-align: center; text-decoration: none; width: 250px; border-radius: 24px; box-shadow: 0 6px 20px rgba(0, 229, 255, 0.45); text-transform: uppercase; letter-spacing: 0.5px;">
                                    Open Support Portal &rarr;
                                </a>
                            </td>
                        </tr>
                    </table>
                </td>
            </tr>

            {get_footer_html(sender_name="La-Vie Helpdesk")}

        </table>
    </center>
</body>
</html>
"""


def render_otp_password_reset_email(
    user_name: str,
    otp_code: str,
    expiry_minutes: int = 10
) -> str:
    """Renders a high-security dark-mode OTP verification email with glowing 6-digit code box."""
    display_name = user_name if user_name and user_name.strip() else "Valued Member"
    spaced_otp = "  ".join(list(otp_code))

    return f"""<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Password Reset Code: {otp_code}</title>
    <style type="text/css">
        {get_base_styles()}
    </style>
</head>
<body style="margin: 0; padding: 0; background-color: #070B19;">
    <center style="width: 100%; background-color: #070B19; padding: 32px 0;">
        <table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%" class="email-container" style="max-width: 600px; margin: 0 auto; background-color: #0E1326; border-radius: 18px; border: 1px solid rgba(0, 229, 255, 0.35); overflow: hidden; box-shadow: 0 12px 36px rgba(0,0,0,0.65);">
            
            {get_header_html(badge_text="🔒 SECURITY VERIFICATION", badge_color="#00E5FF")}

            <!-- CONTENT -->
            <tr>
                <td class="content-padding" style="padding: 20px 40px 28px 40px; color: #C9D1D9; font-size: 15px; line-height: 1.65; text-align: center;">
                    <h1 style="color: #FFFFFF; font-size: 24px; font-weight: 800; margin: 0 0 12px 0; letter-spacing: -0.5px;">
                        Password Reset Verification
                    </h1>
                    <p style="color: #8B949E; font-size: 14px; margin: 0 0 24px 0;">
                        Hello <strong style="color: #FFFFFF;">{display_name}</strong>, we received a request to reset the password for your La-Vie account.
                    </p>

                    <!-- 6-DIGIT OTP BOX -->
                    <div style="background: rgba(0, 229, 255, 0.05); border: 2px solid #00E5FF; border-radius: 14px; padding: 24px; margin: 0 auto 24px auto; max-width: 360px; box-shadow: 0 0 25px rgba(0, 229, 255, 0.25);">
                        <span style="font-size: 12px; color: #8B949E; text-transform: uppercase; letter-spacing: 1.5px; display: block; margin-bottom: 8px;">
                            Your 6-Digit Verification Code
                        </span>
                        <div style="font-family: 'Courier New', Courier, monospace; font-size: 36px; font-weight: 900; color: #00E5FF; letter-spacing: 8px; text-shadow: 0 0 12px rgba(0, 229, 255, 0.6);">
                            {spaced_otp}
                        </div>
                        <span style="font-size: 12px; color: #FFB300; display: block; margin-top: 10px; font-weight: 600;">
                            ⏱️ Expires in {expiry_minutes} minutes
                        </span>
                    </div>

                    <p style="color: #C9D1D9; font-size: 14px; margin: 0 0 16px 0;">
                        Enter this code in the mobile app or browser prompt to choose a new password.
                    </p>

                    <!-- SECURITY WARNING -->
                    <div style="background: rgba(255, 255, 255, 0.03); border: 1px solid rgba(255, 255, 255, 0.08); border-radius: 10px; padding: 14px; font-size: 12px; color: #8B949E; text-align: left; line-height: 1.5;">
                        <strong style="color: #FFFFFF;">⚠️ Didn't request this code?</strong> If you did not initiate a password reset, you can safely ignore this email. Your password will remain unchanged and your account stays secure.
                    </div>
                </td>
            </tr>

            {get_footer_html(sender_name="La-Vie Security Team")}

        </table>
    </center>
</body>
</html>
"""


