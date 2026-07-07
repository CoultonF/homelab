/*
 * Mealie cards for Home Assistant Lovelace.
 *
 * mealie-shopping-card — unchecked items from a Mealie todo entity as a big bulleted list.
 * mealie-week-card     — Mon–Sun of the current week with the planned dinner(s) per day.
 * mealie-recipe-card   — tonight's dinner with full ingredients + directions
 *                        (full-screen panel view for the TRMNL X render).
 *
 * Deployed to /config/www/ on the HAOS NUC and registered as a Lovelace
 * module resource (/local/mealie-cards.js?v=N — bump N after redeploying).
 */
(() => {
  const ordinal = (n) => {
    const s = ["th", "st", "nd", "rd"];
    const v = n % 100;
    return n + (s[(v - 20) % 10] || s[v] || s[0]);
  };

  const esc = (s) =>
    String(s).replace(
      /[&<>"']/g,
      (c) =>
        ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c])
    );

  // Local-date helpers (all-day Mealie events carry plain YYYY-MM-DD dates).
  const ymd = (d) =>
    `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(
      d.getDate()
    ).padStart(2, "0")}`;

  const isoLocal = (d) => {
    const off = -d.getTimezoneOffset();
    const sign = off >= 0 ? "+" : "-";
    const pad = (n) => String(Math.abs(n)).padStart(2, "0");
    return (
      `${ymd(d)}T${pad(d.getHours())}:${pad(d.getMinutes())}:00` +
      `${sign}${pad(Math.trunc(off / 60))}:${pad(off % 60)}`
    );
  };

  const BASE_CSS = `
    ha-card { padding: 20px 24px; box-sizing: border-box; }
    .title { font-size: 2.4rem; font-weight: 700; margin: 0 0 14px; }
    ul { margin: 6px 0 4px; padding-left: 1.3em; }
    li { font-size: 1.8rem; line-height: 1.5; margin: 8px 0; }
    .muted { color: var(--secondary-text-color); }
    .error { color: var(--error-color, #b71c1c); font-size: 1.1rem; }
  `;

  // The week card publishes its rendered height here so the shopping card
  // can cap itself to it (equal columns for static e-ink renders like TRMNL).
  const WEEK_HEIGHT_EVENT = "mealie-week-height";

  const MEAL_LINE_HEIGHT = 1.15; // must match .meal line-height

  // Recipe body font range: never shrink below the e-ink-readable floor —
  // overflow spills to a second page (TRMNL playlist screen) instead.
  const RECIPE_FONT_MIN = 17;
  const RECIPE_FONT_MAX = 34;

  // Scale font-size so the text fills its container width but stays within
  // maxLines wrapped lines — binary search, like TRMNL's data-fit-value.
  const fitText = (el, minPx, maxPx, maxLines) => {
    const fits = (px) => {
      el.style.fontSize = `${px}px`;
      return (
        el.scrollHeight <= px * MEAL_LINE_HEIGHT * maxLines + 2 &&
        el.scrollWidth <= el.clientWidth + 1
      );
    };
    if (fits(maxPx)) return;
    let lo = minPx;
    let hi = maxPx;
    while (hi - lo > 0.5) {
      const mid = (lo + hi) / 2;
      if (fits(mid)) lo = mid;
      else hi = mid;
    }
    el.style.fontSize = `${lo}px`;
  };

  class MealieBaseCard extends HTMLElement {
    constructor() {
      super();
      this.attachShadow({ mode: "open" });
    }

    // horizontal-stack gives children equal flex; an inline style on the host
    // overrides that, letting config set unequal column ratios (flex_weight).
    _applyFlexWeight() {
      if (this._config.flex_weight) {
        this.style.flex = `${this._config.flex_weight} ${this._config.flex_weight} 0%`;
      }
    }

    // Re-fetch only when the backing entity actually changes state.
    set hass(hass) {
      this._hass = hass;
      const st = hass.states[this._config.entity];
      const stamp = st ? `${st.last_updated}|${st.state}` : "missing";
      if (stamp !== this._stamp) {
        this._stamp = stamp;
        this._refresh();
      }
    }

    _renderShell(body) {
      this.shadowRoot.innerHTML = `
        <style>${BASE_CSS}${this.constructor.CSS || ""}</style>
        <ha-card>
          ${
            this._config.title
              ? `<h1 class="title">${esc(this._config.title)}</h1>`
              : ""
          }
          ${body}
        </ha-card>`;
    }

    getCardSize() {
      return 6;
    }
  }

  /* ------------------------------------------------------------------ */

  class MealieShoppingCard extends MealieBaseCard {
    static CSS = `
      .more { font-size: 1.6rem; margin: 4px 0 0 6px; display: none; }
      ul { column-width: 18rem; column-gap: 2.5rem; }
      li { break-inside: avoid; }
    `;

    setConfig(config) {
      this._config = {
        entity: "todo.mealie_weekly",
        title: "Groceries to Buy",
        // Cap the card at the mealie-week-card's height on the same page,
        // hiding overflow behind a "+N more" line. Set max_height (px) to
        // use a fixed cap instead; set both off for natural height.
        match_week_card: true,
        max_height: null,
        ...config,
      };
      this._applyFlexWeight();
      this._stamp = null;
      this._items = [];
    }

    connectedCallback() {
      this._onWeekHeight = () => this._renderBody();
      window.addEventListener(WEEK_HEIGHT_EVENT, this._onWeekHeight);
    }

    disconnectedCallback() {
      window.removeEventListener(WEEK_HEIGHT_EVENT, this._onWeekHeight);
    }

    async _refresh() {
      if (!this._hass) return;
      try {
        const res = await this._hass.callWS({
          type: "todo/item/list",
          entity_id: this._config.entity,
        });
        this._items = (res.items || []).filter(
          (i) => i.status === "needs_action"
        );
        this._error = null;
      } catch (e) {
        this._error = e.message || String(e);
      }
      this._renderBody();
    }

    _renderBody() {
      if (this._error) {
        this._renderShell(
          `<p class="error">Couldn't load ${esc(this._config.entity)}: ${esc(
            this._error
          )}</p>`
        );
        return;
      }
      // Always re-render the full list first so a new (larger) height limit
      // can bring previously truncated items back.
      this._renderShell(
        this._items.length
          ? `<ul>${this._items
              .map((i) => `<li>${esc(i.summary)}</li>`)
              .join("")}</ul><p class="muted more"></p>`
          : `<p class="muted" style="font-size:1.5rem">Nothing to buy</p>`
      );
      this._truncate();
    }

    _truncate() {
      const limit =
        this._config.max_height ||
        (this._config.match_week_card && window.__mealieWeekHeight) ||
        null;
      const card = this.shadowRoot.querySelector("ha-card");
      if (!card) return;
      if (!limit) {
        card.style.removeProperty("height");
        return;
      }
      card.style.height = `${Math.round(limit)}px`;
      card.style.overflow = "hidden";
      const ul = this.shadowRoot.querySelector("ul");
      const more = this.shadowRoot.querySelector(".more");
      if (!ul || !more) return;
      let hidden = 0;
      // Multicol lists can overflow horizontally at a fixed height, so
      // check both axes.
      while (
        (card.scrollHeight > card.clientHeight ||
          card.scrollWidth > card.clientWidth) &&
        ul.children.length
      ) {
        ul.lastElementChild.remove();
        hidden++;
        more.textContent = `+ ${hidden} more`;
        more.style.display = "block";
      }
    }

    static getStubConfig() {
      return { entity: "todo.mealie_weekly", title: "Groceries to Buy" };
    }
  }

  /* ------------------------------------------------------------------ */

  class MealieWeekCard extends MealieBaseCard {
    static CSS = `
      .day { padding: 10px 0 12px 12px; border-left: 4px solid transparent; }
      .day.past { opacity: 0.55; }
      .day.today { border-left-color: var(--primary-color); }
      .day-head { display: flex; justify-content: space-between; align-items: center; gap: 12px; }
      .day-name { font-size: 1.35rem; font-weight: 700; text-transform: uppercase;
                  letter-spacing: 0.06em; padding: 3px 16px; border-radius: 999px;
                  background: var(--secondary-background-color);
                  color: var(--primary-text-color); }
      .today .day-name { background: var(--primary-text-color);
                         color: var(--card-background-color); }
      .day-date { font-size: 1.35rem; color: var(--secondary-text-color); white-space: nowrap; }
      .meal { font-weight: 800; line-height: ${MEAL_LINE_HEIGHT}; margin-top: 4px;
              white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
      .none { font-size: 1.4rem; margin: 6px 0 0 2px; }
      .sep { border: none; border-top: 1px solid var(--divider-color); margin: 2px 0; }
    `;

    setConfig(config) {
      this._config = {
        entity: "calendar.mealie_dinner",
        title: null, // day rows speak for themselves; set to add a header
        ...config,
      };
      this._applyFlexWeight();
      this._stamp = null;
    }

    connectedCallback() {
      // Catch Mealie plan edits and day/week rollover between entity updates.
      this._timer = setInterval(() => this._refresh(), 30 * 60 * 1000);
    }

    disconnectedCallback() {
      clearInterval(this._timer);
      if (this._ro) this._ro.disconnect();
    }

    _publishHeight() {
      const card = this.shadowRoot.querySelector("ha-card");
      if (!card) return;
      const h = card.getBoundingClientRect().height;
      if (h && h !== window.__mealieWeekHeight) {
        window.__mealieWeekHeight = h;
        window.dispatchEvent(new CustomEvent(WEEK_HEIGHT_EVENT, { detail: h }));
      }
    }

    async _refresh() {
      if (!this._hass) return;
      const now = new Date();
      const monday = new Date(
        now.getFullYear(),
        now.getMonth(),
        now.getDate() - ((now.getDay() + 6) % 7)
      );
      const sundayEnd = new Date(
        monday.getFullYear(),
        monday.getMonth(),
        monday.getDate() + 6,
        23,
        59,
        59
      );

      let events;
      try {
        events = await this._hass.callApi(
          "GET",
          `calendars/${this._config.entity}?start=${encodeURIComponent(
            isoLocal(monday)
          )}&end=${encodeURIComponent(isoLocal(sundayEnd))}`
        );
      } catch (e) {
        this._renderShell(
          `<p class="error">Couldn't load ${esc(this._config.entity)}: ${esc(
            e.message || e
          )}</p>`
        );
        return;
      }

      const today = ymd(now);
      const days = [];
      for (let i = 0; i < 7; i++) {
        const d = new Date(
          monday.getFullYear(),
          monday.getMonth(),
          monday.getDate() + i
        );
        const key = ymd(d);
        const meals = events.filter((ev) => {
          if (ev.start?.date) {
            // All-day events: [start, end) may span several days.
            return key >= ev.start.date && key < (ev.end?.date || ev.start.date);
          }
          return (ev.start?.dateTime || "").startsWith(key);
        });
        const cls =
          key === today ? "today" : key < today ? "past" : "";
        days.push(`
          <div class="day ${cls}">
            <div class="day-head">
              <span class="day-name">${d.toLocaleDateString(undefined, {
                weekday: "long",
              })}</span>
              <span class="day-date">${d.toLocaleDateString(undefined, {
                month: "long",
              })} ${ordinal(d.getDate())}, ${d.getFullYear()}</span>
            </div>
            ${
              meals.length
                ? meals
                    .map((m) => `<div class="meal">${esc(m.summary)}</div>`)
                    .join("")
                : `<p class="muted none">&mdash;</p>`
            }
          </div>`);
      }
      this._renderShell(days.join(`<hr class="sep">`));
      const card = this.shadowRoot.querySelector("ha-card");
      this._fitMeals();
      this._lastWidth = card.clientWidth;
      if (this._ro) this._ro.disconnect();
      // Refit only on width changes — refitting changes the card's height,
      // which would otherwise re-trigger the observer in a loop.
      this._ro = new ResizeObserver(() => {
        if (card.clientWidth !== this._lastWidth) {
          this._lastWidth = card.clientWidth;
          this._fitMeals();
        }
        this._publishHeight();
      });
      this._ro.observe(card);
      this._publishHeight();
    }

    _fitMeals() {
      this.shadowRoot
        .querySelectorAll(".meal")
        .forEach((el) => fitText(el, 20, 34, 1));
    }

    static getStubConfig() {
      return { entity: "calendar.mealie_dinner" };
    }

    getCardSize() {
      return 12;
    }
  }

  /* ------------------------------------------------------------------ */

  class MealieRecipeCard extends MealieBaseCard {
    static CSS = `
      ha-card { height: calc(100vh - var(--header-height, 56px));
                padding: 36px 44px 32px; display: flex; flex-direction: column;
                overflow: hidden; position: relative; }
      .cont-hint { position: absolute; right: 44px; bottom: 16px; display: none;
                   font-size: 1.2rem; color: var(--secondary-text-color);
                   background: var(--card-background-color); padding-left: 14px; }
      .eyebrow { font-size: 1.1rem; font-weight: 700; text-transform: uppercase;
                 letter-spacing: 0.1em; color: var(--secondary-text-color); }
      .name { font-size: 3.2rem; font-weight: 800; line-height: 1.1; margin: 6px 0 0; }
      .meta { font-size: 1.3rem; color: var(--secondary-text-color); margin-top: 10px; }
      .body { flex: 1; min-height: 0; display: flex; gap: 3em; margin-top: 28px;
              overflow: hidden; }
      .col-title { font-size: 0.85em; font-weight: 700; text-transform: uppercase;
                   letter-spacing: 0.08em; color: var(--secondary-text-color);
                   margin: 0 0 0.6em; }
      .ings { flex: 1; min-width: 0; }
      .steps { flex: 2; min-width: 0; }
      .body ul { margin: 0; padding-left: 1.1em; }
      .body ul li { font-size: 1em; line-height: 1.4; margin: 0.3em 0; }
      .body ul li.sec { list-style: none; margin: 0.8em 0 0.3em -1.1em;
                        font-weight: 800; }
      .body ol { list-style: none; counter-reset: step; margin: 0; padding: 0; }
      .body ol li { counter-increment: step; display: flex; gap: 0.7em;
                    font-size: 1em; line-height: 1.45; margin: 0 0 0.9em; }
      .body ol li::before { content: counter(step); font-weight: 800; }
      .step-title { font-weight: 800; }
      .center { flex: 1; display: flex; flex-direction: column; justify-content: center;
                align-items: center; text-align: center; gap: 14px; }
      .center .big { font-size: 3.2rem; font-weight: 800; }
      .center .muted { font-size: 1.8rem; }
    `;

    setConfig(config) {
      this._config = {
        entity: "calendar.mealie_dinner", // refresh trigger only
        meal_type: "dinner",
        config_entry_id: null, // Mealie config entry; injected by provisioner
        page: 1, // 1 = first screen; 2 = continuation when the recipe overflows
        ...config,
      };
      this._stamp = null;
    }

    // Keep the embedded fallback week card (see _renderFallback) live.
    set hass(hass) {
      super.hass = hass;
      if (this._fallback) this._fallback.hass = hass;
    }

    connectedCallback() {
      // Catch Mealie plan edits and midnight rollover between entity updates.
      this._timer = setInterval(() => this._refresh(), 30 * 60 * 1000);
    }

    disconnectedCallback() {
      clearInterval(this._timer);
      if (this._ro) this._ro.disconnect();
    }

    async _refresh() {
      if (!this._hass) return;
      this._error = null;
      this._entries = [];
      this._main = null;
      this._recipe = null;
      try {
        if (!this._config.config_entry_id)
          throw new Error("config_entry_id is required");
        const svc = (service, data = {}) =>
          this._hass.callWS({
            type: "call_service",
            domain: "mealie",
            service,
            service_data: {
              config_entry_id: this._config.config_entry_id,
              ...data,
            },
            return_response: true,
          });
        // get_mealplan without dates returns today + tomorrow.
        const plan = (await svc("get_mealplan"))?.response?.mealplan || [];
        const today = ymd(new Date());
        this._entries = plan.filter(
          (p) =>
            p.mealplan_date === today &&
            p.entry_type === this._config.meal_type
        );
        this._main =
          this._entries.find((p) => p.recipe) || this._entries[0] || null;
        if (this._main?.recipe) {
          this._recipe = (
            await svc("get_recipe", {
              recipe_id: this._main.recipe.recipe_id,
            })
          )?.response?.recipe;
        }
      } catch (e) {
        this._error = e.message || String(e);
      }
      this._render();
    }

    _render() {
      const page = this._config.page || 1;
      this._fallback = null;
      const shell = (inner) => {
        this.shadowRoot.innerHTML = `
          <style>${BASE_CSS}${MealieRecipeCard.CSS}</style>
          <ha-card>
            <div class="eyebrow">Tonight${page > 1 ? " · continued" : ""}</div>
            ${inner}
            <div class="cont-hint">&rarr; continued on next screen</div>
          </ha-card>`;
      };

      const r = this._recipe;
      if (this._error) {
        shell(
          `<p class="error">Couldn't load tonight's recipe: ${esc(
            this._error
          )}</p>`
        );
        return;
      }
      // Single-screen states have no continuation — the page-2 view shows
      // the week planner instead of an empty card.
      if (!this._main) {
        if (page > 1) return this._renderFallback();
        shell(`<div class="center"><p class="muted">Nothing planned tonight</p></div>`);
        return;
      }
      if (!r) {
        // Note-only mealplan entry (no linked recipe).
        if (page > 1) return this._renderFallback();
        shell(`
          <div class="center">
            <div class="big">${esc(this._main.title || "Dinner")}</div>
            ${
              this._main.description
                ? `<p class="muted">${esc(this._main.description)}</p>`
                : ""
            }
          </div>`);
        return;
      }

      const serves = Number(r.recipe_servings) || 0;
      const meta = [
        r.total_time && `${r.total_time} total`,
        r.prep_time && `Prep ${r.prep_time}`,
        r.perform_time && `Cook ${r.perform_time}`,
        serves && `Serves ${serves}`,
      ].filter(Boolean);
      const others = this._entries
        .filter((p) => p !== this._main)
        .map((p) => p.recipe?.name || p.title)
        .filter(Boolean);
      if (others.length) meta.push(`Also: ${others.join(", ")}`);

      // Section headers live on the first item of each section (.title).
      const ings = (r.ingredients || [])
        .map((i) => {
          const sec = i.title ? `<li class="sec">${esc(i.title)}</li>` : "";
          const text = i.display || i.note || "";
          return sec + (text ? `<li>${esc(text)}</li>` : "");
        })
        .join("");
      const steps = (r.instructions || [])
        .map(
          (s) =>
            `<li><div>${
              s.title ? `<div class="step-title">${esc(s.title)}</div>` : ""
            }${esc(s.text || "")}</div></li>`
        )
        .join("");

      shell(`
        <h1 class="name">${esc(r.name)}</h1>
        ${
          meta.length
            ? `<div class="meta">${meta.map(esc).join("  ·  ")}</div>`
            : ""
        }
        <div class="body">
          <div class="ings">
            <div class="col-title">Ingredients</div>
            <ul>${ings}</ul>
          </div>
          <div class="steps">
            <div class="col-title">Directions</div>
            <ol>${steps}</ol>
          </div>
        </div>`);

      const status = this._layout();
      if (page > 1 && status === "single") return this._renderFallback();
      const card = this.shadowRoot.querySelector("ha-card");
      this._lastW = card.clientWidth;
      this._lastH = card.clientHeight;
      if (this._ro) this._ro.disconnect();
      // The card's height is viewport-fixed, so refitting never resizes it —
      // safe to refit on any card size change without looping. This also
      // handles the initial render racing the card's attach/layout ("unsized").
      this._ro = new ResizeObserver(() => {
        if (card.clientWidth !== this._lastW || card.clientHeight !== this._lastH) {
          this._lastW = card.clientWidth;
          this._lastH = card.clientHeight;
          const s = this._layout();
          if (page > 1 && s === "single") this._renderFallback();
        }
      });
      this._ro.observe(card);
    }

    // Scale the two-column body (all inner sizes are em-relative) to fill the
    // fixed-height card, but never below RECIPE_FONT_MIN — if the recipe
    // can't fit one screen at that floor, size it for two screens and assign
    // each list item to page 1 or 2. Both dashboard views run this same fit
    // against the same viewport, so the pages always agree on the boundary.
    _layout() {
      const body = this.shadowRoot.querySelector(".body");
      if (!body) return "none";
      // Not attached/laid out yet — the ResizeObserver retries once sized.
      if (!body.clientHeight) return "unsized";
      const page = this._config.page || 1;
      // Reset any previous page assignment first: re-layout must measure the
      // full content, and hidden items would measure as 0x0.
      for (const li of body.querySelectorAll("li")) li.style.display = "";
      const fits = (px, pages) => {
        body.style.fontSize = `${px}px`;
        return (
          body.scrollHeight <= body.clientHeight * pages + 1 &&
          body.scrollWidth <= body.clientWidth + 1
        );
      };
      const bestFit = (pages) => {
        let lo = RECIPE_FONT_MIN;
        let hi = RECIPE_FONT_MAX;
        if (fits(hi, pages)) return;
        while (hi - lo > 0.5) {
          const mid = (lo + hi) / 2;
          if (fits(mid, pages)) lo = mid;
          else hi = mid;
        }
        fits(lo, pages);
      };

      this._split = !fits(RECIPE_FONT_MIN, 1);
      bestFit(this._split ? 2 : 1);

      if (this._split) {
        // Measure every item first, then apply — hiding shifts positions.
        const limit = body.clientHeight;
        const assign = [];
        for (const col of body.querySelectorAll(".ings, .steps")) {
          const colTop = col.getBoundingClientRect().top;
          for (const li of col.querySelectorAll("li")) {
            const r = li.getBoundingClientRect();
            assign.push([li, r.bottom - colTop <= limit + 1]);
          }
        }
        for (const [li, onPage1] of assign) {
          li.style.display = onPage1 === (page === 1) ? "" : "none";
        }
      }
      const hint = this.shadowRoot.querySelector(".cont-hint");
      if (hint)
        hint.style.display = this._split && page === 1 ? "block" : "none";
      return this._split ? "split" : "single";
    }

    // When there's no continuation content, the page-2 playlist slot would
    // be an empty card — show the week planner there instead.
    _renderFallback() {
      if (this._ro) this._ro.disconnect();
      this.shadowRoot.innerHTML = "";
      const week = document.createElement("mealie-week-card");
      week.setConfig({ entity: this._config.entity });
      week.hass = this._hass;
      this._fallback = week;
      this.shadowRoot.appendChild(week);
    }

    static getStubConfig() {
      return { entity: "calendar.mealie_dinner", meal_type: "dinner" };
    }

    getCardSize() {
      return 12;
    }
  }

  customElements.define("mealie-shopping-card", MealieShoppingCard);
  customElements.define("mealie-week-card", MealieWeekCard);
  customElements.define("mealie-recipe-card", MealieRecipeCard);

  window.customCards = window.customCards || [];
  window.customCards.push(
    {
      type: "mealie-shopping-card",
      name: "Mealie Shopping List",
      description: "Large-print list of unchecked Mealie shopping list items",
    },
    {
      type: "mealie-week-card",
      name: "Mealie Week Planner",
      description: "Mon–Sun dinner plan from the Mealie calendar",
    },
    {
      type: "mealie-recipe-card",
      name: "Mealie Tonight's Recipe",
      description:
        "Ingredients and directions for tonight's planned dinner",
    }
  );
})();
