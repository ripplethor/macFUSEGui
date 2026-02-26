/* docs/assets/site.js */
const CONFIG = {
    repo: "ripplethor/macfuseGUI",
    defaultBranch: "main",
    repoApiBase: "https://api.github.com/repos"
};
const root = document.documentElement;

const themeToggle = document.getElementById("theme-toggle");
const themeToggleLabel = document.getElementById("theme-toggle-label");
const downloadBtn = document.getElementById("download-btn");
const githubBtn = document.getElementById("github-btn");
const footerGithubBtn = document.getElementById("footer-github-btn");
const yearSpan = document.getElementById("current-year");

const prefersReducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
const prefersCoarsePointer = window.matchMedia("(pointer: coarse)");
const FX_MODE_STORAGE_KEY = "fx-mode";
let isLiteFxMode = false;

function detectAutoLiteFxMode() {
    const saveData = Boolean(navigator.connection && navigator.connection.saveData);

    return (
        prefersReducedMotion.matches ||
        prefersCoarsePointer.matches ||
        saveData
    );
}

function resolvePreferredFxMode() {
    try {
        const saved = localStorage.getItem(FX_MODE_STORAGE_KEY);
        if (saved === "lite" || saved === "full") {
            return saved;
        }
    } catch (e) { }

    return detectAutoLiteFxMode() ? "lite" : "full";
}

function applyFxMode(mode) {
    isLiteFxMode = mode === "lite";
    root.dataset.fxMode = isLiteFxMode ? "lite" : "full";
}

function initFxMode() {
    applyFxMode(resolvePreferredFxMode());
}

function setupVisibilityPerformance() {
    document.addEventListener("visibilitychange", () => {
        root.classList.toggle("tab-hidden", document.hidden);
    });
}

function initTheme() {
    const savedTheme = localStorage.getItem("theme");
    const prefersDark = window.matchMedia("(prefers-color-scheme: dark)").matches;

    if (savedTheme === "dark") {
        root.classList.add("dark");
    } else if (savedTheme === "light") {
        root.classList.remove("dark");
    } else if (prefersDark) {
        root.classList.add("dark");
    } else {
        root.classList.remove("dark");
    }

    updateThemeUI();
}

function toggleTheme() {
    const nextIsDark = !root.classList.contains("dark");
    root.classList.remove("theme-fading");
    root.classList.toggle("dark", nextIsDark);
    localStorage.setItem("theme", nextIsDark ? "dark" : "light");
    updateThemeUI();
}

function updateThemeUI() {
    const isDark = root.classList.contains("dark");
    if (themeToggle) {
        themeToggle.setAttribute("aria-pressed", String(isDark));
    }
    if (themeToggleLabel) {
        themeToggleLabel.textContent = isDark ? "Switch to Light Mode" : "Switch to Dark Mode";
    }
}

function setupLinks() {
    const releasesUrl = `https://github.com/${CONFIG.repo}/releases/latest`;
    const repoUrl = `https://github.com/${CONFIG.repo}`;

    if (downloadBtn) {
        downloadBtn.href = releasesUrl;
    }
    if (githubBtn) {
        githubBtn.href = repoUrl;
    }
    if (footerGithubBtn) {
        footerGithubBtn.href = repoUrl;
    }
}

function addMediaQueryListener(mediaQueryList, handler) {
    if (typeof mediaQueryList.addEventListener === "function") {
        mediaQueryList.addEventListener("change", handler);
        return;
    }
    if (typeof mediaQueryList.addListener === "function") {
        mediaQueryList.addListener(handler);
    }
}

function setupAdaptiveFxMode() {
    const updateFxMode = () => applyFxMode(resolvePreferredFxMode());
    addMediaQueryListener(prefersReducedMotion, updateFxMode);
    addMediaQueryListener(prefersCoarsePointer, updateFxMode);
}

function setYear() {
    if (yearSpan) {
        yearSpan.textContent = String(new Date().getFullYear());
    }
}

function setupAccordion() {
    const triggers = Array.from(document.querySelectorAll("[data-accordion-trigger]"));
    if (!triggers.length) return;

    function setPanelState(trigger, expanded) {
        const controlsId = trigger.getAttribute("aria-controls");
        const panel = controlsId ? document.getElementById(controlsId) : null;
        trigger.setAttribute("aria-expanded", String(expanded));

        if (panel) {
            panel.classList.toggle("is-open", expanded);
            panel.setAttribute("aria-hidden", String(!expanded));
        }

        const chevron = trigger.querySelector("svg");
        if (chevron) {
            chevron.style.transform = expanded ? "rotate(180deg)" : "rotate(0deg)";
        }

        const parent = trigger.closest('.glass-panel');
        if (parent) {
            parent.classList.toggle('faq-active', expanded);
        }
    }

    function closeOthers(activeTrigger) {
        triggers.forEach((otherTrigger) => {
            if (otherTrigger !== activeTrigger) {
                setPanelState(otherTrigger, false);
            }
        });
    }

    function focusTrigger(index) {
        if (index < 0 || index >= triggers.length) return;
        triggers[index].focus();
    }

    triggers.forEach((trigger, index) => {
        const initiallyExpanded = trigger.getAttribute("aria-expanded") === "true";
        setPanelState(trigger, initiallyExpanded);

        trigger.addEventListener("click", () => {
            const expanded = trigger.getAttribute("aria-expanded") === "true";
            closeOthers(trigger);
            setPanelState(trigger, !expanded);
        });

        trigger.addEventListener("keydown", (event) => {
            if (event.key === "ArrowDown") {
                event.preventDefault();
                focusTrigger((index + 1) % triggers.length);
            } else if (event.key === "ArrowUp") {
                event.preventDefault();
                focusTrigger((index - 1 + triggers.length) % triggers.length);
            } else if (event.key === "Home") {
                event.preventDefault();
                focusTrigger(0);
            } else if (event.key === "End") {
                event.preventDefault();
                focusTrigger(triggers.length - 1);
            }
        });
    });
}

async function updateHeroVersion() {
    const heroVersion = document.getElementById("hero-version");
    if (!heroVersion) return;

    const fallback = heroVersion.textContent?.trim() || "latest";
    const url = `${CONFIG.repoApiBase}/${CONFIG.repo}/releases/latest`;

    try {
        const response = await fetch(url, {
            headers: {
                "Accept": "application/vnd.github+json"
            }
        });
        if (!response.ok) {
            throw new Error(`GitHub releases request failed: ${response.status}`);
        }
        const release = await response.json();
        const tagName = typeof release.tag_name === "string" ? release.tag_name.trim() : "";
        if (!tagName) {
            heroVersion.textContent = fallback;
            return;
        }
        heroVersion.textContent = tagName.startsWith("v") ? tagName : `v${tagName}`;
    } catch (error) {
        heroVersion.textContent = fallback;
    }
}

document.addEventListener("DOMContentLoaded", () => {
    initFxMode();
    initTheme();
    setupLinks();
    setupAdaptiveFxMode();
    setYear();
    setupVisibilityPerformance();
    setupAccordion();
    void updateHeroVersion();

    if (themeToggle) {
        themeToggle.addEventListener("click", toggleTheme);
    }
});
