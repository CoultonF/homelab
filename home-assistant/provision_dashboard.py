# Provision the Mealie dashboards on the HAOS NUC (idempotent).
# Registers /local/mealie-cards.js as a Lovelace resource, then creates (if
# missing) and (re)saves the view config of two dashboards:
#   /meal-planner  — week plan + groceries (TRMNL X screenshot render)
#   /mealie-dinner — tonight's recipe, ingredients + directions (TRMNL X)
#
# Run: uv run --with websockets home-assistant/provision_dashboard.py

import asyncio
import json
import pathlib

import websockets

WS_URL = "ws://192.168.0.96:8123/api/websocket"
TOKEN = pathlib.Path("~/.config/hass_token").expanduser().read_text().strip()

RESOURCE_URL = "/local/mealie-cards.js?v=9"  # bump ?v= after each deploy.sh run
URL_PATH = "meal-planner"  # dashboard url_path must contain a hyphen
DINNER_URL_PATH = "mealie-dinner"

# Panel view: the horizontal-stack spans the full viewport; flex_weight sets
# the 1/3 groceries : 2/3 planner split. Sized for the TRMNL X screenshot
# render (1872x1404 landscape).
DASHBOARD_CONFIG = {
    "views": [
        {
            "title": "Meals",
            "path": "home",
            "type": "panel",
            "cards": [
                {
                    "type": "horizontal-stack",
                    "cards": [
                        {
                            "type": "custom:mealie-shopping-card",
                            "entity": "todo.mealie_weekly",
                            "title": "Groceries to Buy",
                            "flex_weight": 1,
                        },
                        {
                            "type": "custom:mealie-week-card",
                            "entity": "calendar.mealie_dinner",
                            "flex_weight": 2,
                        },
                    ],
                }
            ],
        }
    ]
}


# Tonight's recipe full-screen for the TRMNL X. The card calls the Mealie
# integration's get_mealplan/get_recipe actions, which need the config entry
# id; it's injected here at provision time because looking it up requires an
# admin-only WS call the card can't make for non-admin viewers.
def dinner_dashboard_config(mealie_entry_id):
    def view(page, path, title):
        return {
            "title": title,
            "path": path,
            "type": "panel",
            "cards": [
                {
                    "type": "custom:mealie-recipe-card",
                    "entity": "calendar.mealie_dinner",
                    "meal_type": "dinner",
                    "config_entry_id": mealie_entry_id,
                    "page": page,
                }
            ],
        }

    # Page 2 shows the overflow when the recipe doesn't fit one screen at a
    # readable size (or the week planner when it does). Add both views as
    # TRMNL screenshot playlist items; the touch bar flips between them:
    #   /mealie-dinner  and  /mealie-dinner/page-2
    return {
        "views": [
            view(1, "home", "Dinner Tonight"),
            view(2, "page-2", "Dinner Tonight (continued)"),
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
        existing = next(
            (r for r in resources if r["url"].split("?")[0] == base), None
        )
        if existing is None:
            await ha.cmd(
                type="lovelace/resources/create", res_type="module", url=RESOURCE_URL
            )
            print(f"resource: registered {RESOURCE_URL}")
        elif existing["url"] != RESOURCE_URL:
            await ha.cmd(
                type="lovelace/resources/update",
                resource_id=existing["id"],
                res_type="module",
                url=RESOURCE_URL,
            )
            print(f"resource: updated to {RESOURCE_URL}")
        else:
            print("resource: already registered")

        entries = await ha.cmd(type="config_entries/get", domain="mealie")
        if not entries:
            raise RuntimeError("no Mealie config entry found in HA")
        mealie_entry_id = entries[0]["entry_id"]

        await ensure_dashboard(
            ha,
            url_path=URL_PATH,
            title="Meals",
            icon="mdi:silverware-fork-knife",
            config=DASHBOARD_CONFIG,
        )
        await ensure_dashboard(
            ha,
            url_path=DINNER_URL_PATH,
            title="Dinner Tonight",
            icon="mdi:chef-hat",
            config=dinner_dashboard_config(mealie_entry_id),
        )


async def ensure_dashboard(ha, *, url_path, title, icon, config):
    dashboards = await ha.cmd(type="lovelace/dashboards/list")
    if any(d.get("url_path") == url_path for d in dashboards):
        print(f"dashboard: /{url_path} already exists")
    else:
        await ha.cmd(
            type="lovelace/dashboards/create",
            url_path=url_path,
            title=title,
            icon=icon,
            show_in_sidebar=True,
            require_admin=False,
            mode="storage",
        )
        print(f"dashboard: created /{url_path}")

    await ha.cmd(type="lovelace/config/save", url_path=url_path, config=config)
    print(f"dashboard: /{url_path} view config saved")


asyncio.run(main())
