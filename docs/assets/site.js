/* docs/assets/site.js */
const REPO = "ripplethor/macfuseGUI";

// DOM Elements
const themeToggle = document.getElementById('theme-toggle');
const themeToggleLabel = document.getElementById('theme-toggle-label');
const downloadBtn = document.getElementById('download-btn');
const githubBtn = document.getElementById('github-btn');
const yearSpan = document.getElementById('current-year');

// Theme Logic
function initTheme() {
    const savedTheme = localStorage.getItem('theme');
    const prefersDark = window.matchMedia('(prefers-color-scheme: dark)').matches;

    // Only force if user has explicitly saved a preference
    if (savedTheme === 'dark') {
        document.documentElement.classList.add('dark');
    } else if (savedTheme === 'light') {
        document.documentElement.classList.remove('dark');
    } else {
        // No saved preference: follow system
        if (prefersDark) {
            document.documentElement.classList.add('dark');
        } else {
            document.documentElement.classList.remove('dark');
        }
        // Do NOT write to localStorage here, keeps "system sync" active
    }
    updateThemeUI();
}

function toggleTheme() {
    const isDark = document.documentElement.classList.toggle('dark');
    const newTheme = isDark ? 'dark' : 'light';
    localStorage.setItem('theme', newTheme);
    updateThemeUI();
}

function updateThemeUI() {
    const isDark = document.documentElement.classList.contains('dark');
    if (themeToggle) {
        themeToggle.setAttribute('aria-pressed', isDark);
    }
    if (themeToggleLabel) {
        themeToggleLabel.textContent = isDark ? 'Switch to Light Mode' : 'Switch to Dark Mode';
    }
}

// Dynamic Links
function setupLinks() {
    if (downloadBtn) {
        downloadBtn.href = `https://github.com/${REPO}/releases/latest`;
    }
    if (githubBtn) {
        githubBtn.href = `https://github.com/${REPO}`;
    }

    // Wire up footer GitHub link if present
    const footerGithub = document.getElementById('footer-github-btn');
    if (footerGithub) {
        footerGithub.href = `https://github.com/${REPO}`;
    }
}

// Copyright Year
function setYear() {
    if (yearSpan) {
        yearSpan.textContent = new Date().getFullYear();
    }
}

// FAQ Accordion
function setupAccordion() {
    const triggers = document.querySelectorAll('[data-accordion-trigger]');

    function setPanelState(trigger, panel, isExpanded) {
        trigger.setAttribute('aria-expanded', String(isExpanded));
        if (!panel) return;
        panel.hidden = !isExpanded;
        panel.classList.toggle('hidden', !isExpanded);

        const chevron = trigger.querySelector('svg');
        if (chevron) {
            chevron.style.transform = isExpanded ? 'rotate(180deg)' : 'rotate(0deg)';
        }
    }

    triggers.forEach(trigger => {
        trigger.addEventListener('click', () => {
            const isExpanded = trigger.getAttribute('aria-expanded') === 'true';
            const controlsId = trigger.getAttribute('aria-controls');
            const panel = document.getElementById(controlsId);

            // Keep a clean one-open-at-a-time interaction.
            triggers.forEach(otherTrigger => {
                if (otherTrigger === trigger) return;
                const otherControlsId = otherTrigger.getAttribute('aria-controls');
                const otherPanel = document.getElementById(otherControlsId);
                setPanelState(otherTrigger, otherPanel, false);
            });

            setPanelState(trigger, panel, !isExpanded);
        });

        // Normalize initial state from markup.
        const controlsId = trigger.getAttribute('aria-controls');
        const panel = document.getElementById(controlsId);
        const expanded = trigger.getAttribute('aria-expanded') === 'true';
        if (panel) {
            const shouldExpand = expanded && !panel.classList.contains('hidden') && !panel.hidden;
            setPanelState(trigger, panel, shouldExpand);
        } else {
            trigger.setAttribute('aria-expanded', 'false');
            const chevron = trigger.querySelector('svg');
            if (chevron) {
                chevron.style.transform = 'rotate(0deg)';
            }
        }
    });
}


// Scroll Observer for Animations
function setupScrollObserver() {
    const observerOptions = {
        root: null,
        rootMargin: '0px',
        threshold: 0.1
    };

    const observer = new IntersectionObserver((entries, observer) => {
        entries.forEach(entry => {
            if (entry.isIntersecting) {
                entry.target.classList.add('reveal-visible');
                observer.unobserve(entry.target); // Only animate once
            }
        });
    }, observerOptions);

    const hiddenElements = document.querySelectorAll('.reveal-on-scroll');
    hiddenElements.forEach((el) => observer.observe(el));
}

// Hero Animation (Typewriter)
function initHeroAnimation() {
    const terminalText = document.querySelector('.typing-text');
    if (!terminalText) return;

    const messages = [
        "Resolving host db.production.internal...",
        "Authenticating with public key...",
        "Mounting remote filesystem...",
        "Connection established."
    ];

    let msgIndex = 0;
    let charIndex = 0;
    let isDeleting = false;
    let typeSpeed = 50;

    function type() {
        const currentMsg = messages[msgIndex];

        if (isDeleting) {
            terminalText.textContent = currentMsg.substring(0, charIndex - 1);
            charIndex--;
            typeSpeed = 30;
        } else {
            terminalText.textContent = currentMsg.substring(0, charIndex + 1);
            charIndex++;
            typeSpeed = 50;
        }

        if (!isDeleting && charIndex === currentMsg.length) {
            // Finished typing sentence
            if (msgIndex === messages.length - 1) {
                // Final message, stop
                terminalText.classList.remove('border-r-2'); // Stop blinking cursor
                return;
            }
            isDeleting = true;
            typeSpeed = 1000; // Pause at end
        } else if (isDeleting && charIndex === 0) {
            // Finished deleting
            isDeleting = false;
            msgIndex++;
            typeSpeed = 500; // Pause before next
        }

        setTimeout(type, typeSpeed);
    }

    // Start after initial reveal
    setTimeout(type, 1500);
}

// Initialize
document.addEventListener('DOMContentLoaded', () => {
    // Theme is handled by inline script in head, but we re-run init to sync UI state
    initTheme();

    if (themeToggle) {
        themeToggle.addEventListener('click', toggleTheme);
    }

    setupLinks();
    setYear();
    setupAccordion();
    setupScrollObserver();
    initHeroAnimation();
});
