from dataclasses import dataclass, field
import os
from pathlib import Path

from dotenv import dotenv_values


@dataclass(frozen=True)
class Settings:
    mongodb_uri: str = field(repr=False)
    database: str = "fixora_dev"
    shop_id: str = "fixora-demo-shop"
    jac_url: str = "http://127.0.0.1:8000"
    access_token: str = field(default="", repr=False)
    app_secret: str = field(default="", repr=False)
    verify_token: str = field(default="", repr=False)
    whatsapp_token: str = field(default="", repr=False)
    phone_number_id: str = ""
    graph_version: str = ""
    owner_password: str = field(default="", repr=False)
    owner_origins: tuple[str, ...] = ("http://localhost:8000", "http://127.0.0.1:8000")
    template_name: str = ""
    template_language: str = "en_US"
    model: str = ""
    model_key: str = field(default="", repr=False)
    model_base_url: str = ""
    transcription_model: str = "gpt-4o-mini-transcribe"
    transcription_key: str = field(default="", repr=False)
    # Longer than the bounded 5 x 45 second Jac workflow; renewed between stages.
    lease_seconds: int = 600

    @classmethod
    def load(cls):
        local = dotenv_values(Path.cwd() / ".env", interpolate=False)

        def value(name, default=""):
            return str(os.environ.get(name, local.get(name) or default)).strip()

        model = value("FIXORA_INTAKE_MODEL", value("FIXORA_MODEL"))
        provider_key = "GOOGLE_API_KEY" if model.startswith("gemini/") else "OPENAI_API_KEY"
        if model.startswith(("anthropic/", "claude-")):
            provider_key = "ANTHROPIC_API_KEY"
        elif model.startswith("openrouter/"):
            provider_key = "OPENROUTER_API_KEY"
        return cls(
            mongodb_uri=value("FIXORA_MONGODB_URI", value("MONGODB_URI")),
            database=value("MONGODB_DB", "fixora_dev"),
            jac_url=value("FIXORA_JAC_URL", "http://127.0.0.1:8000").rstrip("/"),
            access_token=value("FIXORA_ACCESS_TOKEN"),
            app_secret=value("WHATSAPP_APP_SECRET"),
            verify_token=value("WHATSAPP_VERIFY_TOKEN"),
            whatsapp_token=value("WHATSAPP_ACCESS_TOKEN"),
            phone_number_id=value("WHATSAPP_PHONE_NUMBER_ID"),
            graph_version=value("WHATSAPP_GRAPH_VERSION"),
            owner_password=value("FIXORA_OWNER_PASSWORD"),
            owner_origins=tuple(x.strip() for x in value("FIXORA_OWNER_ORIGINS", "http://localhost:8000,http://127.0.0.1:8000").split(",") if x.strip()),
            template_name=value("WHATSAPP_UPDATE_TEMPLATE"),
            template_language=value("WHATSAPP_TEMPLATE_LANGUAGE", "en_US"),
            model=model,
            model_key=value("FIXORA_MODEL_API_KEY", value(provider_key, value("GEMINI_API_KEY"))),
            model_base_url=value("FIXORA_MODEL_BASE_URL"),
            transcription_model=value("FIXORA_TRANSCRIPTION_MODEL", "gpt-4o-mini-transcribe"),
            transcription_key=value("FIXORA_TRANSCRIPTION_API_KEY", value("OPENAI_API_KEY")),
        )

    def require(self, role):
        required = {"FIXORA_MONGODB_URI": self.mongodb_uri}
        if role == "public":
            required.update(WHATSAPP_APP_SECRET=self.app_secret, WHATSAPP_VERIFY_TOKEN=self.verify_token,
                            WHATSAPP_PHONE_NUMBER_ID=self.phone_number_id)
        elif role == "owner":
            required.update(FIXORA_OWNER_PASSWORD=self.owner_password, FIXORA_ACCESS_TOKEN=self.access_token)
        elif role == "worker":
            required.update(FIXORA_ACCESS_TOKEN=self.access_token, WHATSAPP_ACCESS_TOKEN=self.whatsapp_token,
                            WHATSAPP_PHONE_NUMBER_ID=self.phone_number_id, WHATSAPP_GRAPH_VERSION=self.graph_version)
        missing = [name for name, val in required.items() if not val]
        if missing:
            raise RuntimeError("Missing configuration: " + ", ".join(missing))
        if not self.mongodb_uri.startswith(("mongodb://", "mongodb+srv://")):
            raise RuntimeError("Set a valid MongoDB URI.")
        if role == "owner" and len(self.owner_password) < 16:
            raise RuntimeError("FIXORA_OWNER_PASSWORD must contain at least 16 characters.")
