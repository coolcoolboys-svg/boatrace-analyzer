"""Stop packaging when the app's support contact has drifted."""
import json
from pathlib import Path
root = Path(__file__).resolve().parents[1]
config = json.loads((root / "release-support.json").read_text())
assert config["supportEmail"] == "kojinapp.support@gmail.com", "Unexpected support mailbox"
assert config["appReviewContactEmail"] == config["supportEmail"]
assert config["betaFeedbackEmail"] == config["supportEmail"]
texts = [(root / path).read_text() for path in config["contactSourcePaths"]]
assert any(config["supportEmail"] in text for text in texts), "App mailbox is missing"
assert config.get("supportMethod") == "email", "Support must use email only"
assert "supportFormUrl" not in config, "Obsolete support form configuration"
assert not any("docs.google.com/forms/" in text or "SUPPORT_FORM_URL" in text for text in texts), "Obsolete support form link"
assert not any("mybus.fukuoka@gmail.com" in text for text in texts), "Obsolete support address"
print("Support contact verified:", config["supportEmail"])
