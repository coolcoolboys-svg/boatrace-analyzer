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
assert any(config["supportFormUrl"] in text for text in texts), "App form link is missing"
assert not any("mybus.fukuoka@gmail.com" in text for text in texts), "Obsolete support address"
print("Support contact verified:", config["supportEmail"])
