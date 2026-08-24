"""
Automated Test Suite for Conference Web UI Dropup & Settings Modal
"""
import os

def test_html_structure():
    with open(r"c:\xampp\htdocs\conferenceMe\static\index.html", "r", encoding="utf-8") as f:
        html = f.read()

    # 1. Check toggleMoreBtn exists
    assert 'id="toggleMoreBtn"' in html, "toggleMoreBtn button missing in index.html"
    
    # 2. Check moreOptionsMenu exists
    assert 'id="moreOptionsMenu"' in html, "moreOptionsMenu dropdown missing in index.html"
    
    # 3. Check settingsModal exists
    assert 'id="settingsModal"' in html, "settingsModal missing in index.html"
    
    # 4. Check toggleSettingsMenuBtn exists in more options
    assert 'id="toggleSettingsMenuBtn"' in html, "toggleSettingsMenuBtn missing in moreOptionsMenu"

    # 5. Check emojiPopover exists
    assert 'id="emojiPopover"' in html, "emojiPopover missing in index.html"

    print("[PASS] test_html_structure")

def test_css_rules():
    with open(r"c:\xampp\htdocs\conferenceMe\static\style.css", "r", encoding="utf-8") as f:
        css = f.read()

    # 1. Verify overflow is NOT hidden/auto on media-controls globally
    assert "overflow: visible !important" in css, "media-controls must have overflow: visible !important"

    # 2. Verify #moreOptionsMenu has bottom positioning and high z-index
    assert "#moreOptionsMenu" in css, "#moreOptionsMenu rule missing in style.css"
    assert "bottom: calc(100% + 14px)" in css, "moreOptionsMenu must have bottom dropup position"
    assert "z-index: 99999" in css, "moreOptionsMenu must have top z-index"

    # 3. Verify no unmatched braces
    open_braces = css.count("{")
    close_braces = css.count("}")
    assert open_braces == close_braces, f"Mismatched braces in style.css! Open: {open_braces}, Close: {close_braces}"

    print("[PASS] test_css_rules")

def test_js_event_listeners():
    with open(r"c:\xampp\htdocs\conferenceMe\static\app.js", "r", encoding="utf-8") as f:
        js = f.read()

    # 1. Verify toggleMoreBtn click listener exists
    assert "toggleMoreBtn.addEventListener('click'" in js, "toggleMoreBtn click listener missing in app.js"

    # 2. Verify toggleSettingsMenuBtn click listener exists
    assert "toggleSettingsMenuBtn.addEventListener('click'" in js, "toggleSettingsMenuBtn click listener missing in app.js"

    # 3. Verify navSettingsBtn click listener exists
    assert "navSettingsBtn.addEventListener('click'" in js, "navSettingsBtn click listener missing in app.js"

    # 4. Verify populateSettingsDevices exists
    assert "function populateSettingsDevices" in js, "populateSettingsDevices function missing in app.js"

    print("[PASS] test_js_event_listeners")

if __name__ == "__main__":
    print("--- Running Automated UI Test Suite ---")
    test_html_structure()
    test_css_rules()
    test_js_event_listeners()
    print("--- ALL TESTS PASSED SUCCESSFULLY! ---")
