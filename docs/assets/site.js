/* docs/assets/site.js */
const REPO = "ripplethor/macfuseGUI";
const root = document.documentElement;

const themeToggle = document.getElementById("theme-toggle");
const themeToggleLabel = document.getElementById("theme-toggle-label");
const downloadBtn = document.getElementById("download-btn");
const githubBtn = document.getElementById("github-btn");
const footerGithubBtn = document.getElementById("footer-github-btn");
const yearSpan = document.getElementById("current-year");

const prefersReducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
const prefersCoarsePointer = window.matchMedia("(pointer: coarse)");
const prefersSmallViewport = window.matchMedia("(max-width: 1200px)");
const THEME_FADE_IN_MS = 260;
const THEME_FADE_OUT_MS = 320;
const FX_MODE_STORAGE_KEY = "fx-mode";
let themeTransitionTimer = 0;
let isLiteFxMode = false;

function detectAutoLiteFxMode() {
    const saveData = Boolean(navigator.connection && navigator.connection.saveData);
    const memoryGiB = typeof navigator.deviceMemory === "number" ? navigator.deviceMemory : null;
    const logicalCores = typeof navigator.hardwareConcurrency === "number" ? navigator.hardwareConcurrency : null;
    const lowMemory = memoryGiB !== null && memoryGiB <= 8;
    const modestCpu = logicalCores !== null && logicalCores <= 8;

    return (
        prefersReducedMotion.matches ||
        prefersCoarsePointer.matches ||
        prefersSmallViewport.matches ||
        saveData ||
        lowMemory ||
        modestCpu
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

    if (isLiteFxMode || prefersReducedMotion.matches) {
        root.classList.remove("motion-enabled");
    } else {
        root.classList.add("motion-enabled");
    }
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

    if (prefersReducedMotion.matches) {
        root.classList.toggle("dark", nextIsDark);
        localStorage.setItem("theme", nextIsDark ? "dark" : "light");
        updateThemeUI();
        return;
    }

    window.clearTimeout(themeTransitionTimer);
    if (root.classList.contains("theme-fading")) return;

    root.classList.add("theme-fading");
    themeTransitionTimer = window.setTimeout(() => {
        root.classList.toggle("dark", nextIsDark);
        localStorage.setItem("theme", nextIsDark ? "dark" : "light");
        updateThemeUI();

        themeTransitionTimer = window.setTimeout(() => {
            root.classList.remove("theme-fading");
        }, THEME_FADE_OUT_MS);
    }, THEME_FADE_IN_MS);
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
    const releasesUrl = `https://github.com/${REPO}/releases/latest`;
    const repoUrl = `https://github.com/${REPO}`;

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
            panel.hidden = !expanded;
            panel.classList.toggle("hidden", !expanded);
        }

        const chevron = trigger.querySelector("svg");
        if (chevron) {
            chevron.style.transform = expanded ? "rotate(180deg)" : "rotate(0deg)";
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

function setupHeaderMotion() {
    const header = document.querySelector("header");
    if (!header) return;

    const syncHeader = () => {
        header.dataset.scrolled = window.scrollY > 8 ? "true" : "false";
    };

    syncHeader();
    window.addEventListener("scroll", syncHeader, { passive: true });
}

function delayForElement(element) {
    if (element.classList.contains("delay-300")) return 210;
    if (element.classList.contains("delay-200")) return 140;
    if (element.classList.contains("delay-100")) return 70;
    return 0;
}

function variantForElement(element, index) {
    if (element.dataset.reveal) return element.dataset.reveal;
    if (element.classList.contains("text-center")) return "up-soft";
    const cycle = ["up", "left", "right", "up-soft"];
    return cycle[index % cycle.length];
}

function setupScrollReveal() {
    const elements = Array.from(document.querySelectorAll(".reveal-on-scroll"));
    if (!elements.length) return;

    elements.forEach((element, index) => {
        element.style.setProperty("--reveal-delay", `${delayForElement(element)}ms`);
        element.dataset.reveal = variantForElement(element, index);
    });

    const showAll = () => {
        elements.forEach((element) => element.classList.add("reveal-visible"));
    };

    const hideAll = () => {
        elements.forEach((element) => element.classList.remove("reveal-visible"));
    };

    let rafId = 0;
    let listenersAttached = false;

    const runRevealPass = () => {
        rafId = 0;
        const vh = window.innerHeight || root.clientHeight;
        const revealLine = vh * 0.96;
        const activeTop = vh * 0.02;
        const resetTop = -vh * 0.22;
        const resetBottom = vh * 1.18;

        elements.forEach((element) => {
            const rect = element.getBoundingClientRect();
            const shouldReveal = rect.top <= revealLine && rect.bottom >= activeTop;
            const fullyOutOfRange = rect.bottom < resetTop || rect.top > resetBottom;

            if (shouldReveal) {
                element.classList.add("reveal-visible");
            } else if (fullyOutOfRange) {
                element.classList.remove("reveal-visible");
            }
        });
    };

    const scheduleRevealPass = () => {
        if (rafId) return;
        rafId = window.requestAnimationFrame(runRevealPass);
    };

    const onScroll = () => scheduleRevealPass();
    const onResize = () => scheduleRevealPass();
    const onOrientationChange = () => scheduleRevealPass();

    const start = () => {
        if (listenersAttached) return;
        listenersAttached = true;
        window.addEventListener("scroll", onScroll, { passive: true });
        window.addEventListener("resize", onResize);
        window.addEventListener("orientationchange", onOrientationChange);
        runRevealPass();
    };

    const stop = () => {
        if (!listenersAttached) return;
        listenersAttached = false;
        window.removeEventListener("scroll", onScroll);
        window.removeEventListener("resize", onResize);
        window.removeEventListener("orientationchange", onOrientationChange);
        if (rafId) {
            window.cancelAnimationFrame(rafId);
            rafId = 0;
        }
    };

    const syncMotionMode = () => {
        if (prefersReducedMotion.matches || isLiteFxMode) {
            stop();
            root.classList.remove("motion-enabled");
            showAll();
        } else {
            root.classList.add("motion-enabled");
            hideAll();
            start();
        }
    };

    if (typeof prefersReducedMotion.addEventListener === "function") {
        prefersReducedMotion.addEventListener("change", syncMotionMode);
    } else if (typeof prefersReducedMotion.addListener === "function") {
        prefersReducedMotion.addListener(syncMotionMode);
    }

    syncMotionMode();
}

function setupHeroParallax() {
    if (prefersReducedMotion.matches || isLiteFxMode) return;

    const heroStage = document.querySelector(".perspective-1000 > div");
    if (!heroStage) return;
    heroStage.classList.add("hero-stage");

    let rafId = 0;
    let targetX = 0;
    let targetY = 0;
    let currentX = 0;
    let currentY = 0;

    const clamp = (value, min, max) => Math.max(min, Math.min(max, value));

    const animate = () => {
        rafId = 0;
        currentX += (targetX - currentX) * 0.12;
        currentY += (targetY - currentY) * 0.12;

        const lift = Math.abs(currentY) * 0.45 + Math.abs(currentX) * 0.2;
        heroStage.style.transform = `perspective(1400px) rotateX(${currentY.toFixed(2)}deg) rotateY(${currentX.toFixed(2)}deg) translate3d(0, ${(-lift).toFixed(2)}px, 0)`;

        if (Math.abs(targetX - currentX) > 0.02 || Math.abs(targetY - currentY) > 0.02) {
            rafId = window.requestAnimationFrame(animate);
        }
    };

    const requestTick = () => {
        if (!rafId) {
            rafId = window.requestAnimationFrame(animate);
        }
    };

    const handlePointerMove = (event) => {
        const rect = heroStage.getBoundingClientRect();
        const x = (event.clientX - rect.left) / rect.width - 0.5;
        const y = (event.clientY - rect.top) / rect.height - 0.5;

        targetX = clamp(x * 6, -6, 6);
        targetY = clamp(-y * 5, -5, 5);
        requestTick();
    };

    const handlePointerLeave = () => {
        targetX = 0;
        targetY = 0;
        requestTick();
    };

    heroStage.addEventListener("pointermove", handlePointerMove);
    heroStage.addEventListener("pointerleave", handlePointerLeave);
}

document.addEventListener("DOMContentLoaded", () => {
    initFxMode();
    initTheme();
    setupLinks();
    setYear();
    setupVisibilityPerformance();
    setupAccordion();
    setupHeaderMotion();
    setupScrollReveal();
    setupHeroParallax();

    if (themeToggle) {
        themeToggle.addEventListener("click", toggleTheme);
    }
});
