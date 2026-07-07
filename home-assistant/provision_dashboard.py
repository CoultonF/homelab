# Provision the "Meals" dashboard on the HAOS NUC (idempotent).
# Registers /local/mealie-cards.js as a Lovelace resource, creates the
# meal-planner dashboard if missing, and (re)saves its view config.
#
# Run: uv run --with websockets home-assistant/provision_dashboard.py

import asyncio
import json
import pathlib

import websockets

WS_URL = "ws://192.168.0.96:8123/api/websocket"
TOKEN = pathlib.Path("~/.config/hass_token").expanduser().read_text().strip()

RESOURCE_URL = "/local/mealie-cards.js?v=1"
URL_PATH = "meal-planner"  # dashboard url_path must contain a hyphen

DASHBOARD_CONFIG = {
    "views": [
        {
            "title": "Meals",
            "path": "home",
            "type": "sections",
            "max_columns": 2,
            "sections": [
                {
                    "type": "grid",
                    "cards": [
                        {
                            "type": "custom:mealie-shopping-card",
                            "entity": "todo.mealie_weekly",
                            "title": "Groceries to Buy",
                        }
                    ],
                },
                {
                    "type": "grid",
                    "cards": [
                        {
                            "type": "custom:mealie-week-card",
                            "entity": "calendar.mealie_dinner",
                            "title": "Meal Planner",
                        }
                    ],
                },
            ],
        }
    ]
}


class HA:
    def __init__(self, ws):
        self.ws = ws
        self.msg_id = 0

    async def cmd(self, **payload):
        self.msg_id += 1
        payload["id"] = self.msg_id
        await self.ws.send(json.dumps(payload))
        while True:
            msg = json.loads(await self.ws.recv())
            if msg.get("id") == self.msg_id and msg.get("type") == "result":
                if not msg["success"]:
                    raise RuntimeError(f"{payload['type']} failed: {msg['error']}")
                return msg.get("result")


async def main():
    async with websockets.connect(WS_URL) as ws:
        assert json.loads(await ws.recv())["type"] == "auth_required"
        await ws.send(json.dumps({"type": "auth", "access_token": TOKEN}))
        auth = json.loads(await ws.recv())
        assert auth["type"] == "auth_ok", auth
        ha = HA(ws)

        resources = await ha.cmd(type="lovelace/resources")
        base = RESOURCE_URL.split("?")[0]
        if any(r["url"].split("?")[0] == base for r in resources):
            print("resource: already registered")
        else:
            await ha.cmd(
                type="lovelace/resources/create", res_type="module", url=RESOURCE_URL
            )
            print(f"resource: registered {RESOURCE_URL}")

        dashboards = await ha.cmd(type="lovelace/dashboards/list")
        if any(d.get("url_path") == URL_PATH for d in dashboards):
            print("dashboard: already exists")
        else:
            await ha.cmd(
                type="lovelace/dashboards/create",
                url_path=URL_PATH,
                title="Meals",
                icon="mdi:silverware-fork-knife",
                show_in_sidebar=True,
                require_admin=False,
                mode="storage",
            )
            print(f"dashboard: created /{URL_PATH}")

        await ha.cmd(
            type="lovelace/config/save", url_path=URL_PATH, config=DASHBOARD_CONFIG
        )
        print("dashboard: view config saved")


asyncio.run(main())
