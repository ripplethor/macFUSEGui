export const siteConfig = {
  siteUrl: "https://www.macfusegui.app",
  repoUrl: "https://github.com/ripplethor/macfuseGUI",
  releasesUrl: "https://github.com/ripplethor/macfuseGUI/releases/latest",
  licenseUrl: "https://github.com/ripplethor/macfuseGUI/blob/main/LICENSE",
};

export const localeDefinitions = [
  {
    slug: "en",
    hreflang: "en",
    htmlLang: "en",
    ogLocale: "en_US",
    englishLabel: "English",
    nativeLabel: "English",
  },
  {
    slug: "zh-hans",
    hreflang: "zh-Hans",
    htmlLang: "zh-Hans",
    ogLocale: "zh_CN",
    englishLabel: "Chinese (Simplified)",
    nativeLabel: "简体中文",
  },
  {
    slug: "ja",
    hreflang: "ja",
    htmlLang: "ja",
    ogLocale: "ja_JP",
    englishLabel: "Japanese",
    nativeLabel: "日本語",
  },
  {
    slug: "de",
    hreflang: "de",
    htmlLang: "de",
    ogLocale: "de_DE",
    englishLabel: "German",
    nativeLabel: "Deutsch",
  },
  {
    slug: "fr",
    hreflang: "fr",
    htmlLang: "fr",
    ogLocale: "fr_FR",
    englishLabel: "French",
    nativeLabel: "Français",
  },
  {
    slug: "pt-br",
    hreflang: "pt-BR",
    htmlLang: "pt-BR",
    ogLocale: "pt_BR",
    englishLabel: "Portuguese (Brazil)",
    nativeLabel: "Português (Brasil)",
  },
  {
    slug: "es",
    hreflang: "es",
    htmlLang: "es",
    ogLocale: "es_ES",
    englishLabel: "Spanish",
    nativeLabel: "Español",
  },
  {
    slug: "ko",
    hreflang: "ko",
    htmlLang: "ko",
    ogLocale: "ko_KR",
    englishLabel: "Korean",
    nativeLabel: "한국어",
  },
];

export const pageDefinitions = [
  {
    id: "home",
    slug: "",
    fileName: "index.html",
    layout: "home",
    keywordTargets: ["macFUSE GUI", "SSHFS", "macOS"],
  },
  {
    id: "product",
    slug: "macfuse-gui.html",
    fileName: "macfuse-gui.html",
    layout: "guide",
    keywordTargets: ["macFUSE GUI", "SSHFS", "macOS"],
  },
  {
    id: "sshfs",
    slug: "sshfs-gui-mac.html",
    fileName: "sshfs-gui-mac.html",
    layout: "guide",
    keywordTargets: ["SSHFS GUI", "macOS", "macFUSEGui"],
  },
  {
    id: "install",
    slug: "install-macfuse-sshfs-mac.html",
    fileName: "install-macfuse-sshfs-mac.html",
    layout: "guide",
    keywordTargets: ["macFUSE", "SSHFS", "macOS"],
  },
  {
    id: "troubleshooting",
    slug: "macfusegui-troubleshooting.html",
    fileName: "macfusegui-troubleshooting.html",
    layout: "guide",
    keywordTargets: ["macFUSEGui", "SSHFS", "macOS"],
  },
];

function deepMerge(base, override) {
  if (Array.isArray(base) || Array.isArray(override)) {
    return override !== undefined ? override : base;
  }
  if (
    base &&
    override &&
    typeof base === "object" &&
    typeof override === "object"
  ) {
    const merged = { ...base };
    for (const [key, value] of Object.entries(override)) {
      merged[key] = key in base ? deepMerge(base[key], value) : value;
    }
    return merged;
  }
  return override !== undefined ? override : base;
}

const englishContent = {
  ui: {
    languageLabel: "Language",
    nav: {
      home: "Home",
      product: "macFUSE GUI",
      sshfs: "SSHFS GUI",
      install: "Install",
      troubleshooting: "Troubleshooting",
    },
    footer: {
      home: "Home",
      install: "Install",
      troubleshooting: "Troubleshooting",
      github: "GitHub",
      license: "Licensed under GPLv3. See LICENSE.",
    },
    actions: {
      downloadLatest: "Download Latest Release",
      downloadDmg: "Download DMG",
      viewSource: "View Source",
      openInstallGuide: "Open Install Guide",
      openTroubleshooting: "Open Troubleshooting",
      compareWorkflows: "Compare SSHFS GUI Workflows",
      readProductGuide: "Read the macFUSE GUI Guide",
      recheckInstall: "Recheck Install Steps",
      backToProductGuide: "Back to Product Guide",
      openReleasePage: "Open Latest Release",
    },
    labels: {
      relatedGuides: "Related guides",
      breadcrumbHome: "Home",
      breadcrumb: "Breadcrumb",
      localeSwitcher: "Choose a language",
      guideSection: "Guide map",
      productHighlights: "Why teams use macFUSEGui",
      stepLabel: "Step",
      themeToggle: "Toggle Theme",
      switchToDarkMode: "Switch to Dark Mode",
      switchToLightMode: "Switch to Light Mode",
    },
    copyright: "macFUSEGui. Open Source Contributors.",
  },
  brandAlt: "macFUSE GUI logo for SSHFS on macOS",
  pages: {
    home: {
      cardTitle: "macFUSE GUI for macOS",
      cardDescription:
        "Start here for a native SSHFS workflow on macOS with macFUSEGui.",
      title: "macFUSE GUI for macOS | SSHFS Mount Manager App",
      metaDescription:
        "Use macFUSE GUI on macOS to manage SSHFS mounts from the menu bar with Keychain security, reconnect recovery, and Apple Silicon or Intel downloads.",
      structuredDescription:
        "macFUSE GUI for macOS to manage SSHFS mounts with macFUSE, sshfs, and a native menu bar workflow.",
      hero: {
        eyebrow: "Native macOS mount manager",
        titleTop: "macFUSE GUI SSHFS",
        titleBottom: "for macOS.",
        lead:
          "Stop rebuilding fragile mount commands. macFUSEGui gives macOS teams a focused macFUSE GUI for SSHFS, with per-remote controls, Keychain-backed credentials, diagnostics, and recovery after sleep or network changes.",
        supporting:
          "Choose the right guide below, download the latest build, and keep Apple Silicon and Intel installs on a clean, repeatable path.",
        actions: [
          { kind: "download", style: "primary", labelKey: "downloadDmg", id: "download-btn" },
          { kind: "page", pageId: "product", style: "secondary" },
          { kind: "page", pageId: "install", style: "secondary" },
        ],
      },
      heroSpotlight: {
        versionFallback: "latest",
        title: "SSHFS mounts with status, recovery, and macOS-native controls.",
        bullets: [
          "Independent connect and disconnect for each remote.",
          "Keychain-backed credentials instead of copied secrets.",
          "Recovery after sleep, wake, Wi-Fi changes, and stale unmounts.",
          "Diagnostics you can copy before escalating a mount failure.",
        ],
      },
      guideSection: {
        title: "Choose the guide that matches your search intent",
        intro:
          "The site is organized around the exact problems people search for: understanding the product, comparing SSHFS GUI workflows, getting installed fast, and fixing failed mounts.",
      },
      benefitsSection: {
        title: "Why teams use macFUSEGui",
        intro:
          "The app sits above macFUSE and sshfs so remote folders behave like normal macOS directories in Finder, editors, and daily workflows.",
        cards: [
          {
            title: "Fast setup",
            body: "Save remotes once, test them from the UI, and stop copying long SSHFS commands into Terminal.",
          },
          {
            title: "Auto-reconnect",
            body: "Desired remotes recover after sleep, wake, Wi-Fi changes, and external unmount events.",
          },
          {
            title: "Keychain security",
            body: "Passwords live in macOS Keychain while non-secret remote settings stay in JSON.",
          },
          {
            title: "Per-remote control",
            body: "Connect or disconnect one mount without blocking other active remotes.",
          },
          {
            title: "Diagnostics",
            body: "Copy environment checks, remote states, and recent logs before you start guessing.",
          },
          {
            title: "Editor handoff",
            body: "Mounted folders open cleanly in Finder and the app's editor-plugin flow.",
          },
        ],
      },
      installSection: {
        title: "Install and first-launch path",
        intro:
          "Install macFUSE and sshfs first, then pick the correct build for your CPU architecture and complete the one-time macOS approval flow.",
        methodsTitle: "Install methods",
        methods: [
          {
            title: "Homebrew Cask",
            body: "Use the tap + cask path for repeatable installs and updates.",
            code: "brew tap ripplethor/macfusegui https://github.com/ripplethor/macfuseGUI && brew install --cask ripplethor/macfusegui/macfusegui",
          },
          {
            title: "Terminal Installer",
            body: "Fetch the latest release installer and let the script choose the right artifact.",
            code: '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/ripplethor/macfuseGUI/main/scripts/install_release.sh)"',
          },
          {
            title: "Manual DMG",
            body: "Download the correct DMG for your Mac and drag the app into Applications.",
          },
        ],
        prerequisitesTitle: "Prerequisites",
        prerequisitesParagraphs: [
          "macFUSEGui does not replace macFUSE or sshfs. It manages them. Install both before you expect a stable SSHFS mount on macOS.",
          "If your setup already uses the Homebrew core formula, you can also test <code class=\"font-mono text-sm\">brew install sshfs</code> after macFUSE is installed.",
        ],
        prerequisitesCode:
          "brew install --cask macFUSE\nbrew install gromgit/fuse/sshfs-mac",
        downloadTitle: "Choose your download",
        downloadParagraphs: [
          "Apple Silicon Macs use <code class=\"font-mono text-sm\">arm64</code>. Intel Macs use <code class=\"font-mono text-sm\">x86_64</code>. Confirm your architecture first so you do not debug the wrong build.",
          "On the release page, choose the DMG that ends with <code class=\"font-mono text-sm\">-macos-arm64.dmg</code> or <code class=\"font-mono text-sm\">-macos-x86_64.dmg</code>.",
        ],
        downloadCode: "uname -m",
        checklistTitle: "First-launch checklist",
        checklist: [
          {
            title: "Pick an install method",
            body: "Use Homebrew, the one-line installer, or the direct DMG depending on how much automation you want.",
          },
          {
            title: "Open from Finder once",
            body: "Right-click or Control-click the app and choose Open so macOS records the first-launch approval.",
          },
          {
            title: "Approve in Privacy & Security",
            body: "If macOS blocks the app, use System Settings > Privacy & Security and choose Open Anyway.",
          },
        ],
      },
      howItWorks: {
        title: "How it works",
        intro:
          "macFUSEGui is the control plane. macFUSE provides the filesystem layer, sshfs handles the transport, and the app manages the workflow around both.",
        points: [
          "Builds safe mount commands and manages connect, disconnect, and recovery.",
          "Keeps passwords in macOS Keychain instead of shell history.",
          "Stores non-secret remote settings in <code class=\"font-mono text-sm\">~/Library/Application Support/macfuseGui/remotes.json</code>.",
          "Surfaces diagnostics when installs, auth, or recovery behavior go wrong.",
        ],
      },
      faq: {
        title: "FAQ",
        intro:
          "Quick answers for setup, security, reliability, and the difference between a macFUSE GUI and raw SSHFS commands.",
        items: [
          {
            question: "Do I still need to install macFUSE and sshfs?",
            answer:
              "Yes. macFUSEGui is the UX and control layer. macFUSE and sshfs still provide the underlying filesystem and transport behavior.",
          },
          {
            question: "Can I manage multiple remotes at once?",
            answer:
              "Yes. Each remote has its own state and controls, so you can connect, disconnect, and monitor mounts independently.",
          },
          {
            question: "Where are passwords stored?",
            answer:
              "Passwords are stored in macOS Keychain. The JSON config only keeps non-secret remote settings.",
          },
          {
            question: "What happens after sleep or a network change?",
            answer:
              "Desired remotes are rechecked and reconnected with controlled recovery behavior after wake, reachability changes, or external unmount events.",
          },
          {
            question: "Can I open mounted paths in Finder and code editors?",
            answer:
              "Yes. Once connected, mounted paths behave like normal folders in Finder and can be opened through the app's editor-plugin flow.",
          },
          {
            question: "What if the first launch is blocked?",
            answer:
              "Open the app once from Finder with right-click Open, then approve it in System Settings > Privacy & Security if macOS still warns.",
          },
        ],
      },
    },
    product: {
      cardTitle: "macFUSE GUI for macOS",
      cardDescription:
        "Understand how macFUSEGui fits above macFUSE and sshfs on macOS.",
      title: "macFUSE GUI for macOS | Install and Use macFUSEGui",
      metaDescription:
        "Learn what a macFUSE GUI does on macOS, how macFUSEGui works with macFUSE and SSHFS, and how to install it for reliable remote mounts.",
      hero: {
        eyebrow: "Product guide",
        lead:
          "A <strong>macFUSE GUI</strong> makes SSHFS practical on macOS when you need more than a one-off mount. macFUSEGui sits above macFUSE and <code class=\"font-mono text-sm\">sshfs</code>, then gives you menu bar controls, Keychain-backed secrets, diagnostics, and recovery.",
        actions: [
          { kind: "download", style: "primary", labelKey: "downloadLatest", id: "download-btn" },
          { kind: "repo", style: "secondary", id: "github-btn" },
          { kind: "page", pageId: "install", style: "secondary", labelKey: "openInstallGuide" },
        ],
      },
      sections: [
        {
          type: "cards",
          title: "How the stack fits together",
          intro:
            "The workflow is easier to reason about when the layers are separated: filesystem, transport, and orchestration.",
          cards: [
            {
              title: "macFUSE",
              body: "Provides the filesystem layer that makes a remote path appear as a normal directory on macOS.",
            },
            {
              title: "sshfs",
              body: "Handles the SSH-based transport that mounts a remote path into Finder and your editor.",
            },
            {
              title: "macFUSEGui",
              body: "Adds saved remotes, status, recovery, diagnostics, and editor handoff around both layers.",
            },
          ],
          columns: 3,
        },
        {
          type: "copy",
          title: "Why use a GUI instead of raw sshfs commands?",
          paragraphs: [
            "A shell-only flow is fine when you mount one server once in a while. It becomes brittle when you manage several remotes, switch networks, or need fast visibility into whether a mount is healthy.",
          ],
          bullets: [
            "Per-remote connect and disconnect actions instead of rebuilding commands by hand.",
            "Keychain-backed password storage instead of copied secrets in shell history.",
            "Recovery after sleep, wake, network restoration, and external unmounts.",
            "Diagnostics you can copy when a mount hangs or fails.",
          ],
        },
        {
          type: "copy",
          title: "Install prerequisites",
          paragraphs: [
            "macFUSEGui manages macFUSE and sshfs; it does not replace them. Install both first, then choose the correct app build for your Mac.",
            "If <code class=\"font-mono text-sm\">uname -m</code> prints <code class=\"font-mono text-sm\">arm64</code>, use the Apple Silicon build. If it prints <code class=\"font-mono text-sm\">x86_64</code>, use the Intel build.",
          ],
          code: "brew install --cask macFUSE\nbrew install gromgit/fuse/sshfs-mac\n\nuname -m",
        },
        {
          type: "copy",
          title: "First launch on macOS",
          paragraphs: [
            "Current public builds are unsigned and not notarized. Open the app once from Finder with right-click or Control-click and choose <strong>Open</strong>.",
            "If macOS still blocks the launch, approve it from <strong>System Settings > Privacy & Security</strong> and retry.",
          ],
        },
        {
          type: "copy",
          title: "Typical daily workflow",
          ordered: [
            "Save a remote with host, username, auth mode, remote path, and local mount point.",
            "Test the connection from the app before you rely on Finder or an editor.",
            "Connect the remote, work inside the mounted folder, then disconnect when you are done.",
            "Let the app handle sleep, wake, and network recovery for desired remotes.",
          ],
        },
        {
          type: "copy",
          title: "When to use the troubleshooting guide",
          paragraphs: [
            "Open troubleshooting when first-launch approval succeeds but mounts still fail, credentials look correct but the remote never appears, or a previously healthy mount stops responding after sleep or a network change.",
          ],
          actions: [
            { kind: "page", pageId: "troubleshooting", style: "primary", labelKey: "openTroubleshooting" },
            { kind: "page", pageId: "sshfs", style: "secondary", labelKey: "compareWorkflows" },
          ],
        },
      ],
    },
    sshfs: {
      cardTitle: "SSHFS GUI for Mac",
      cardDescription:
        "Compare a GUI-first SSHFS workflow on macOS with manual shell commands.",
      title: "SSHFS GUI for Mac | Manage SSHFS Mounts with macFUSEGui",
      metaDescription:
        "See what an SSHFS GUI on Mac solves, how macFUSEGui compares with a CLI-only workflow, and when Finder-mounted remotes beat manual SSHFS commands.",
      hero: {
        eyebrow: "Workflow guide",
        lead:
          "An <strong>SSHFS GUI for Mac</strong> turns remote mounts into a workflow you can trust day after day. Instead of rebuilding long commands, you can connect remotes from the menu bar, see whether they are healthy, and reopen them quickly in Finder or your editor.",
        actions: [
          { kind: "download", style: "primary", labelKey: "downloadLatest", id: "download-btn" },
          { kind: "page", pageId: "product", style: "secondary", labelKey: "readProductGuide" },
        ],
      },
      sections: [
        {
          type: "copy",
          title: "What an SSHFS GUI solves on macOS",
          paragraphs: [
            "Manual SSHFS is workable for one-off mounts. It gets noisy when you manage several hosts, need repeatable mount points, or lose confidence after wake, sleep, or flaky Wi-Fi.",
          ],
          bullets: [
            "Mount health is visible without parsing terminal output.",
            "Saved remotes reduce repeated typing and copy-paste mistakes.",
            "Credentials stay in Keychain instead of ad hoc shell scripts.",
            "Finder and editor workflows feel local once the remote path is mounted.",
          ],
        },
        {
          type: "cards",
          title: "CLI-only SSHFS vs GUI-first SSHFS",
          intro:
            "The shell is flexible, but the GUI-first path removes a lot of repetitive operational work.",
          cards: [
            {
              title: "CLI-only SSHFS",
              body: "Powerful and scriptable, but you own retries, state checking, mount-point hygiene, and copied command history.",
            },
            {
              title: "GUI-first SSHFS",
              body: "Better when you want saved remotes, clear status, reconnect behavior, diagnostics, and consistent Finder access.",
            },
          ],
          columns: 2,
        },
        {
          type: "copy",
          title: "Finder-mounted remote folders vs SFTP clients",
          paragraphs: [
            "SFTP clients are fine for occasional file transfer. A mounted SSHFS folder is better when you want local-style tooling: Finder previews, editor indexing, and standard folder-based workflows.",
          ],
        },
        {
          type: "copy",
          title: "Where macFUSEGui fits",
          paragraphs: [
            "macFUSEGui is the control layer on top of macFUSE and sshfs. It focuses on per-remote lifecycle management, Keychain storage, recovery after system events, and diagnostics when something fails.",
          ],
          actions: [
            { kind: "page", pageId: "install", style: "primary", labelKey: "openInstallGuide" },
            { kind: "page", pageId: "troubleshooting", style: "secondary", labelKey: "openTroubleshooting" },
          ],
        },
      ],
    },
    install: {
      cardTitle: "Install macFUSE and SSHFS on Mac",
      cardDescription:
        "Go from prerequisites to a working macFUSEGui mount on macOS.",
      title: "Install macFUSE and SSHFS on Mac | macFUSEGui Guide",
      metaDescription:
        "Install macFUSE and SSHFS on Mac, choose the right macFUSEGui build, complete first-launch approval, and get to your first reliable remote mount.",
      hero: {
        eyebrow: "Install guide",
        lead:
          "Use this page when you want the fastest path from prerequisites to a working mount. Install <strong>macFUSE</strong>, install <strong>SSHFS</strong>, choose the correct build, complete first-launch approval, and test your first remote.",
        actions: [
          { kind: "download", style: "primary", labelKey: "downloadLatest", id: "download-btn" },
          { kind: "page", pageId: "troubleshooting", style: "secondary", labelKey: "openTroubleshooting" },
        ],
      },
      sections: [
        {
          type: "copy",
          title: "Step 1: Install prerequisites",
          paragraphs: [
            "Install macFUSE first, then install sshfs. macFUSEGui depends on both for the underlying filesystem and transport behavior.",
          ],
          code: "brew install --cask macFUSE\nbrew install gromgit/fuse/sshfs-mac",
        },
        {
          type: "copy",
          title: "Step 2: Choose the correct build",
          paragraphs: [
            "Run <code class=\"font-mono text-sm\">uname -m</code> to confirm your CPU architecture. Use the Apple Silicon build for <code class=\"font-mono text-sm\">arm64</code> and the Intel build for <code class=\"font-mono text-sm\">x86_64</code>.",
            "Choosing the wrong build is a common avoidable install mistake when someone forwards a link or downloads from another machine.",
          ],
          code: "uname -m",
        },
        {
          type: "copy",
          title: "Step 3: Complete first-launch approval",
          paragraphs: [
            "Current public builds are unsigned and not notarized. Open the app from Finder with right-click or Control-click and choose <strong>Open</strong>.",
            "If macOS blocks the app, approve it from <strong>System Settings > Privacy & Security</strong> and retry.",
          ],
        },
        {
          type: "copy",
          title: "Step 4: Add your first remote",
          ordered: [
            "Create a remote entry with host, username, auth mode, remote path, and local mount point.",
            "Test the connection from the UI before you rely on the mount in Finder.",
            "Connect the remote and open the mounted path in Finder or your editor.",
          ],
        },
        {
          type: "copy",
          title: "Step 5: If install fails",
          bullets: [
            "Recheck that both macFUSE and sshfs are installed.",
            "Make sure you downloaded the correct build for your Mac.",
            "Confirm the first-launch approval flow completed successfully.",
            "Use troubleshooting for auth, mount-point, reconnect, or stale-mount issues.",
          ],
          actions: [
            { kind: "page", pageId: "troubleshooting", style: "primary", labelKey: "openTroubleshooting" },
            { kind: "page", pageId: "product", style: "secondary" },
          ],
        },
      ],
    },
    troubleshooting: {
      cardTitle: "macFUSEGui Troubleshooting",
      cardDescription:
        "Fix install, auth, mount-point, and recovery problems with macFUSEGui.",
      title: "macFUSEGui Troubleshooting | Fix SSHFS Mount Issues on Mac",
      metaDescription:
        "Fix macFUSEGui issues on macOS, including first-launch approval, auth errors, stale SSHFS mounts, mount-point conflicts, and reconnect failures.",
      hero: {
        eyebrow: "Support guide",
        lead:
          "Use this page when a mount refuses to connect, a previously healthy remote becomes stale after sleep, or macOS blocks the app on first launch. The goal is to isolate whether the failure is in prerequisites, auth, mount state, or recovery behavior.",
        actions: [
          { kind: "page", pageId: "install", style: "primary", labelKey: "recheckInstall" },
          { kind: "download", style: "secondary", labelKey: "downloadLatest", id: "download-btn" },
        ],
      },
      sections: [
        {
          type: "copy",
          title: "1. Prerequisite failures",
          paragraphs: [
            "If the app cannot mount anything, verify that both macFUSE and sshfs are installed. The app depends on them for the actual filesystem and transport work.",
          ],
          code: "brew install --cask macFUSE\nbrew install gromgit/fuse/sshfs-mac",
        },
        {
          type: "copy",
          title: "2. First-launch approval problems",
          paragraphs: [
            "Unsigned public builds require a one-time approval. If the app bounces or appears blocked, open it from Finder with right-click or Control-click and choose <strong>Open</strong>.",
            "Then inspect <strong>System Settings > Privacy & Security</strong> for the approval prompt.",
          ],
        },
        {
          type: "copy",
          title: "3. Authentication and host problems",
          bullets: [
            "Confirm hostname, username, and remote path are correct.",
            "Retest credentials from the app instead of assuming an old saved remote still matches the server.",
            "If you pasted a password, resave it cleanly so you are not debugging a copied typo.",
          ],
        },
        {
          type: "copy",
          title: "4. Mount-point conflicts",
          paragraphs: [
            "A healthy SSH connection can still fail if the local mount point collides with another remote or points at a stale mount path. Use a unique local mount directory for each remote and disconnect stale mounts before retrying.",
          ],
        },
        {
          type: "copy",
          title: "5. Sleep, wake, and network recovery issues",
          paragraphs: [
            "macFUSEGui is designed to recover desired remotes after sleep, wake, or network restoration. If a remote stays stale, disconnect it, verify the network path is actually back, then reconnect.",
            "If the problem repeats, capture diagnostics so you can see which recovery stage failed.",
          ],
        },
        {
          type: "copy",
          title: "6. Stale or broken mounts",
          paragraphs: [
            "If Finder shows a remote but the path no longer responds, treat it as a stale mount problem. Disconnect from the app first. If that does not clear it, re-open the app, verify the mount state, and avoid deleting the remote until the stale mount is gone.",
          ],
        },
        {
          type: "copy",
          title: "7. Use diagnostics before guessing",
          paragraphs: [
            "The diagnostics snapshot exists to replace guesswork. Copy it when you hit repeated failures so you can see environment readiness, remote state, and recent mount or recovery events in one place.",
          ],
          actions: [
            { kind: "page", pageId: "product", style: "primary", labelKey: "backToProductGuide" },
            { kind: "page", pageId: "sshfs", style: "secondary", labelKey: "compareWorkflows" },
          ],
        },
      ],
    },
  },
};

const localeUiOverrides = {
  "zh-hans": {
    ui: {
      languageLabel: "语言",
      nav: {
        home: "首页",
        product: "macFUSE GUI",
        sshfs: "SSHFS GUI",
        install: "安装",
        troubleshooting: "故障排查",
      },
      footer: {
        home: "首页",
        install: "安装",
        troubleshooting: "故障排查",
        github: "GitHub",
        license: "基于 GPLv3 许可发布。参见 LICENSE。",
      },
      actions: {
        downloadLatest: "下载最新版本",
        downloadDmg: "下载 DMG",
        viewSource: "查看源码",
        openInstallGuide: "打开安装指南",
        openTroubleshooting: "打开故障排查",
        compareWorkflows: "比较 SSHFS GUI 工作流",
        readProductGuide: "阅读 macFUSE GUI 指南",
        recheckInstall: "重新检查安装步骤",
        backToProductGuide: "返回产品指南",
        openReleasePage: "打开最新发布页",
      },
      labels: {
        relatedGuides: "相关指南",
        breadcrumbHome: "首页",
        breadcrumb: "面包屑导航",
        localeSwitcher: "选择语言",
        guideSection: "指南地图",
        productHighlights: "为什么团队选择 macFUSEGui",
        stepLabel: "步骤",
        themeToggle: "切换主题",
        switchToDarkMode: "切换到深色模式",
        switchToLightMode: "切换到浅色模式",
      },
      copyright: "macFUSEGui。开源贡献者。",
    },
    brandAlt: "适用于 macOS SSHFS 的 macFUSE GUI 标志",
  },
  ja: {
    ui: {
      languageLabel: "言語",
      nav: {
        home: "ホーム",
        product: "macFUSE GUI",
        sshfs: "SSHFS GUI",
        install: "インストール",
        troubleshooting: "トラブルシューティング",
      },
      footer: {
        home: "ホーム",
        install: "インストール",
        troubleshooting: "トラブルシューティング",
        github: "GitHub",
        license: "GPLv3 で公開。LICENSE を参照してください。",
      },
      actions: {
        downloadLatest: "最新リリースをダウンロード",
        downloadDmg: "DMG をダウンロード",
        viewSource: "ソースを見る",
        openInstallGuide: "インストールガイドを開く",
        openTroubleshooting: "トラブルシューティングを開く",
        compareWorkflows: "SSHFS GUI ワークフローを比較",
        readProductGuide: "macFUSE GUI ガイドを読む",
        recheckInstall: "インストール手順を再確認",
        backToProductGuide: "製品ガイドに戻る",
        openReleasePage: "最新リリースを開く",
      },
      labels: {
        relatedGuides: "関連ガイド",
        breadcrumbHome: "ホーム",
        breadcrumb: "パンくずリスト",
        localeSwitcher: "言語を選択",
        guideSection: "ガイド一覧",
        productHighlights: "macFUSEGui が選ばれる理由",
        stepLabel: "手順",
        themeToggle: "テーマを切り替える",
        switchToDarkMode: "ダークモードに切り替える",
        switchToLightMode: "ライトモードに切り替える",
      },
      copyright: "macFUSEGui。オープンソース貢献者。",
    },
    brandAlt: "macOS SSHFS 向け macFUSE GUI ロゴ",
  },
  de: {
    ui: {
      languageLabel: "Sprache",
      nav: {
        home: "Start",
        product: "macFUSE GUI",
        sshfs: "SSHFS GUI",
        install: "Installation",
        troubleshooting: "Fehlerbehebung",
      },
      footer: {
        home: "Start",
        install: "Installation",
        troubleshooting: "Fehlerbehebung",
        github: "GitHub",
        license: "Veröffentlicht unter GPLv3. Siehe LICENSE.",
      },
      actions: {
        downloadLatest: "Neueste Version laden",
        downloadDmg: "DMG herunterladen",
        viewSource: "Quellcode ansehen",
        openInstallGuide: "Installationsanleitung öffnen",
        openTroubleshooting: "Fehlerbehebung öffnen",
        compareWorkflows: "SSHFS-GUI-Workflows vergleichen",
        readProductGuide: "macFUSE-GUI-Leitfaden lesen",
        recheckInstall: "Installationsschritte prüfen",
        backToProductGuide: "Zurück zum Produktleitfaden",
        openReleasePage: "Neueste Release-Seite öffnen",
      },
      labels: {
        relatedGuides: "Verwandte Leitfäden",
        breadcrumbHome: "Start",
        breadcrumb: "Pfadnavigation",
        localeSwitcher: "Sprache wählen",
        guideSection: "Leitfadenübersicht",
        productHighlights: "Warum Teams macFUSEGui nutzen",
        stepLabel: "Schritt",
        themeToggle: "Theme umschalten",
        switchToDarkMode: "Zum Dunkelmodus wechseln",
        switchToLightMode: "Zum Hellmodus wechseln",
      },
      copyright: "macFUSEGui. Open-Source-Mitwirkende.",
    },
    brandAlt: "macFUSE-GUI-Logo für SSHFS auf macOS",
  },
  fr: {
    ui: {
      languageLabel: "Langue",
      nav: {
        home: "Accueil",
        product: "macFUSE GUI",
        sshfs: "SSHFS GUI",
        install: "Installation",
        troubleshooting: "Dépannage",
      },
      footer: {
        home: "Accueil",
        install: "Installation",
        troubleshooting: "Dépannage",
        github: "GitHub",
        license: "Distribué sous GPLv3. Voir LICENSE.",
      },
      actions: {
        downloadLatest: "Télécharger la dernière version",
        downloadDmg: "Télécharger le DMG",
        viewSource: "Voir le code source",
        openInstallGuide: "Ouvrir le guide d'installation",
        openTroubleshooting: "Ouvrir le dépannage",
        compareWorkflows: "Comparer les workflows SSHFS GUI",
        readProductGuide: "Lire le guide macFUSE GUI",
        recheckInstall: "Revoir les étapes d'installation",
        backToProductGuide: "Retour au guide produit",
        openReleasePage: "Ouvrir la dernière release",
      },
      labels: {
        relatedGuides: "Guides liés",
        breadcrumbHome: "Accueil",
        breadcrumb: "Fil d'Ariane",
        localeSwitcher: "Choisir la langue",
        guideSection: "Carte des guides",
        productHighlights: "Pourquoi les équipes choisissent macFUSEGui",
        stepLabel: "Étape",
        themeToggle: "Changer de thème",
        switchToDarkMode: "Passer au mode sombre",
        switchToLightMode: "Passer au mode clair",
      },
      copyright: "macFUSEGui. Contributeurs open source.",
    },
    brandAlt: "logo macFUSE GUI pour SSHFS sur macOS",
  },
  "pt-br": {
    ui: {
      languageLabel: "Idioma",
      nav: {
        home: "Início",
        product: "macFUSE GUI",
        sshfs: "SSHFS GUI",
        install: "Instalação",
        troubleshooting: "Solução de problemas",
      },
      footer: {
        home: "Início",
        install: "Instalação",
        troubleshooting: "Solução de problemas",
        github: "GitHub",
        license: "Licenciado sob GPLv3. Veja LICENSE.",
      },
      actions: {
        downloadLatest: "Baixar a versão mais recente",
        downloadDmg: "Baixar DMG",
        viewSource: "Ver código-fonte",
        openInstallGuide: "Abrir guia de instalação",
        openTroubleshooting: "Abrir solução de problemas",
        compareWorkflows: "Comparar fluxos SSHFS GUI",
        readProductGuide: "Ler guia do macFUSE GUI",
        recheckInstall: "Revisar etapas de instalação",
        backToProductGuide: "Voltar ao guia do produto",
        openReleasePage: "Abrir página da release",
      },
      labels: {
        relatedGuides: "Guias relacionados",
        breadcrumbHome: "Início",
        breadcrumb: "Trilha de navegação",
        localeSwitcher: "Escolher idioma",
        guideSection: "Mapa dos guias",
        productHighlights: "Por que equipes usam macFUSEGui",
        stepLabel: "Passo",
        themeToggle: "Alternar tema",
        switchToDarkMode: "Mudar para o modo escuro",
        switchToLightMode: "Mudar para o modo claro",
      },
      copyright: "macFUSEGui. Colaboradores de código aberto.",
    },
    brandAlt: "logotipo macFUSE GUI para SSHFS no macOS",
  },
  es: {
    ui: {
      languageLabel: "Idioma",
      nav: {
        home: "Inicio",
        product: "macFUSE GUI",
        sshfs: "SSHFS GUI",
        install: "Instalación",
        troubleshooting: "Solución de problemas",
      },
      footer: {
        home: "Inicio",
        install: "Instalación",
        troubleshooting: "Solución de problemas",
        github: "GitHub",
        license: "Publicado bajo GPLv3. Ver LICENSE.",
      },
      actions: {
        downloadLatest: "Descargar la última versión",
        downloadDmg: "Descargar DMG",
        viewSource: "Ver código fuente",
        openInstallGuide: "Abrir guía de instalación",
        openTroubleshooting: "Abrir solución de problemas",
        compareWorkflows: "Comparar flujos SSHFS GUI",
        readProductGuide: "Leer la guía de macFUSE GUI",
        recheckInstall: "Revisar pasos de instalación",
        backToProductGuide: "Volver a la guía del producto",
        openReleasePage: "Abrir la última release",
      },
      labels: {
        relatedGuides: "Guías relacionadas",
        breadcrumbHome: "Inicio",
        breadcrumb: "Ruta de navegación",
        localeSwitcher: "Elegir idioma",
        guideSection: "Mapa de guías",
        productHighlights: "Por qué los equipos usan macFUSEGui",
        stepLabel: "Paso",
        themeToggle: "Cambiar tema",
        switchToDarkMode: "Cambiar al modo oscuro",
        switchToLightMode: "Cambiar al modo claro",
      },
      copyright: "macFUSEGui. Colaboradores de código abierto.",
    },
    brandAlt: "logotipo de macFUSE GUI para SSHFS en macOS",
  },
  ko: {
    ui: {
      languageLabel: "언어",
      nav: {
        home: "홈",
        product: "macFUSE GUI",
        sshfs: "SSHFS GUI",
        install: "설치",
        troubleshooting: "문제 해결",
      },
      footer: {
        home: "홈",
        install: "설치",
        troubleshooting: "문제 해결",
        github: "GitHub",
        license: "GPLv3로 배포됩니다. LICENSE를 확인하세요.",
      },
      actions: {
        downloadLatest: "최신 버전 다운로드",
        downloadDmg: "DMG 다운로드",
        viewSource: "소스 보기",
        openInstallGuide: "설치 가이드 열기",
        openTroubleshooting: "문제 해결 열기",
        compareWorkflows: "SSHFS GUI 워크플로 비교",
        readProductGuide: "macFUSE GUI 가이드 읽기",
        recheckInstall: "설치 단계 다시 확인",
        backToProductGuide: "제품 가이드로 돌아가기",
        openReleasePage: "최신 릴리스 열기",
      },
      labels: {
        relatedGuides: "관련 가이드",
        breadcrumbHome: "홈",
        breadcrumb: "탐색 경로",
        localeSwitcher: "언어 선택",
        guideSection: "가이드 맵",
        productHighlights: "팀이 macFUSEGui를 선택하는 이유",
        stepLabel: "단계",
        themeToggle: "테마 전환",
        switchToDarkMode: "다크 모드로 전환",
        switchToLightMode: "라이트 모드로 전환",
      },
      copyright: "macFUSEGui. 오픈 소스 기여자.",
    },
    brandAlt: "macOS SSHFS용 macFUSE GUI 로고",
  },
};

const localePageOverrides = {
  "zh-hans": {
    pages: {
      home: {
        cardTitle: "适用于 macOS 的 macFUSE GUI",
        cardDescription: "从这里开始，使用 macFUSEGui 在 macOS 上获得原生 SSHFS 工作流。",
        title: "macFUSE GUI for macOS | SSHFS 挂载管理应用",
        metaDescription:
          "在 macOS 上使用 macFUSE GUI 管理 SSHFS 挂载，获得菜单栏控制、Keychain 安全、断线恢复，以及 Apple Silicon 与 Intel 下载选项。",
        structuredDescription:
          "用于 macOS 的 macFUSE GUI，可借助 macFUSE、sshfs 和原生菜单栏工作流管理 SSHFS 挂载。",
        hero: {
          eyebrow: "原生 macOS 挂载管理器",
          titleTop: "macFUSE GUI SSHFS",
          titleBottom: "for macOS.",
          lead:
            "别再反复拼接脆弱的挂载命令。macFUSEGui 为 macOS 团队提供专注的 macFUSE GUI，用于 SSHFS，包含按远程分离的控制、Keychain 凭证、诊断快照，以及睡眠和网络变化后的恢复能力。",
          supporting:
            "先选对与你搜索意图匹配的指南，再下载正确的构建，把 Apple Silicon 与 Intel 安装流程都保持在可重复、可支持的路径上。",
        },
        heroSpotlight: {
          versionFallback: "最新",
          title: "SSHFS 挂载具备状态、恢复能力，以及符合 macOS 习惯的原生控制。",
          bullets: [
            "每个远程都可独立连接和断开。",
            "凭证保存在 Keychain，而不是复制散落的机密信息。",
            "可在睡眠、唤醒、Wi-Fi 变化和陈旧卸载后执行恢复。",
            "在上报挂载失败前，可先复制诊断信息。",
          ],
        },
        guideSection: {
          title: "选择与你搜索意图匹配的指南",
          intro:
            "网站按真实问题组织：了解产品定位、比较 SSHFS GUI 工作流、快速完成安装，以及在挂载失败时快速定位原因。",
        },
        benefitsSection: {
          title: "为什么团队选择 macFUSEGui",
          intro:
            "应用位于 macFUSE 和 sshfs 之上，让远程目录在 Finder、编辑器和日常工具中像本地文件夹一样工作。",
          cards: [
            { title: "快速设置", body: "远程保存一次即可，直接在 UI 中测试连接，不再反复复制长串 SSHFS 命令。" },
            { title: "自动恢复", body: "期望保持连接的远程会在睡眠、唤醒、Wi‑Fi 变化和外部卸载后自动恢复。" },
            { title: "Keychain 安全", body: "密码保存在 macOS Keychain，中性的远程配置仍保留在 JSON 中。" },
            { title: "按远程独立控制", body: "单独连接或断开某个挂载，不会阻塞其他活动远程。" },
            { title: "诊断快照", body: "在猜测之前先复制环境检查、远程状态和最近日志。" },
            { title: "编辑器接力", body: "已挂载目录可直接在 Finder 和编辑器插件流程中打开。" },
          ],
        },
        installSection: {
          title: "安装与首次启动路径",
          intro:
            "先安装 macFUSE 和 sshfs，再按 CPU 架构选择正确构建，最后完成一次性的 macOS 启动授权。",
          methodsTitle: "安装方式",
          methods: [
            {
              title: "Homebrew Cask",
              body: "适合需要可重复安装和更新路径的团队或个人环境。",
              code: "brew tap ripplethor/macfusegui https://github.com/ripplethor/macfuseGUI && brew install --cask ripplethor/macfusegui/macfusegui",
            },
            {
              title: "终端安装脚本",
              body: "获取最新发布的安装脚本，让它为当前机器选择正确的制品。",
              code: '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/ripplethor/macfuseGUI/main/scripts/install_release.sh)"',
            },
            {
              title: "手动 DMG",
              body: "直接下载与你的 Mac 匹配的 DMG，然后拖入 Applications。",
            },
          ],
          prerequisitesTitle: "前置依赖",
          prerequisitesParagraphs: [
            "macFUSEGui 不会取代 macFUSE 或 sshfs，它负责管理它们。想在 macOS 上获得稳定的 SSHFS 挂载，必须先装好这两个依赖。",
            "如果你的环境已经使用 Homebrew core 公式，也可以在安装 macFUSE 后尝试 <code class=\"font-mono text-sm\">brew install sshfs</code>。",
          ],
          downloadTitle: "选择正确下载包",
          downloadParagraphs: [
            "Apple Silicon 机器使用 <code class=\"font-mono text-sm\">arm64</code>，Intel 机器使用 <code class=\"font-mono text-sm\">x86_64</code>。先确认架构，再下载正确的构建。",
            "在发布页中，选择文件名以 <code class=\"font-mono text-sm\">-macos-arm64.dmg</code> 或 <code class=\"font-mono text-sm\">-macos-x86_64.dmg</code> 结尾的包。",
          ],
          checklistTitle: "首次启动清单",
          checklist: [
            { title: "选择安装方式", body: "根据你是否需要自动化更新，选择 Homebrew、安装脚本或直接下载 DMG。" },
            { title: "先从 Finder 打开一次", body: "右键或 Control‑click 应用并选择“打开”，让 macOS 记录首次启动授权。" },
            { title: "在隐私与安全性中批准", body: "如果系统仍阻止应用，请前往“系统设置 > 隐私与安全性”点击“仍要打开”或同等授权入口。" },
          ],
        },
        howItWorks: {
          title: "工作方式",
          intro:
            "macFUSEGui 是控制层。macFUSE 提供文件系统能力，sshfs 提供传输能力，而应用围绕它们处理连接、恢复和诊断。",
          points: [
            "构建安全的挂载命令，并管理连接、断开和恢复流程。",
            "把密码放入 macOS Keychain，而不是散落在 shell 历史记录里。",
            "把非敏感远程配置写入 <code class=\"font-mono text-sm\">~/Library/Application Support/macfuseGui/remotes.json</code>。",
            "在安装、认证或恢复失败时输出可复制的诊断信息。",
          ],
        },
        faq: {
          title: "常见问题",
          intro: "快速回答安装、安全性、稳定性，以及 macFUSE GUI 与原始 SSHFS 命令之间的差异。",
          items: [
            {
              question: "我还需要安装 macFUSE 和 sshfs 吗？",
              answer: "需要。macFUSEGui 是体验和控制层，底层文件系统与传输仍然依赖 macFUSE 和 sshfs。",
            },
            {
              question: "可以同时管理多个远程吗？",
              answer: "可以。每个远程都有自己的状态和按钮，你可以独立连接、断开和观察挂载健康度。",
            },
            {
              question: "密码存在哪里？",
              answer: "密码保存在 macOS Keychain，JSON 配置只存储非敏感的远程设置。",
            },
            {
              question: "睡眠或网络切换后会发生什么？",
              answer: "应用会重新检查并恢复期望连接的远程，对唤醒、可达性变化和外部卸载做受控处理。",
            },
            {
              question: "可以直接在 Finder 或编辑器里打开挂载路径吗？",
              answer: "可以。连接成功后，挂载路径会像普通文件夹一样使用，也能通过编辑器插件流程打开。",
            },
            {
              question: "如果首次启动被阻止怎么办？",
              answer: "先在 Finder 中右键打开应用一次，如果仍被阻止，再去“系统设置 > 隐私与安全性”中批准。",
            },
          ],
        },
      },
      product: {
        cardTitle: "适用于 macOS 的 macFUSE GUI",
        cardDescription: "了解 macFUSEGui 在 macOS 上如何位于 macFUSE 与 sshfs 之上。",
        title: "macFUSE GUI for macOS | 安装并使用 macFUSEGui",
        metaDescription:
          "了解 macFUSE GUI 在 macOS 上能做什么、macFUSEGui 如何配合 macFUSE 与 SSHFS，以及如何完成安装并稳定使用远程挂载。",
        hero: {
          eyebrow: "产品指南",
          lead:
            "<strong>macFUSE GUI</strong> 让 SSHFS 在 macOS 上从一次性命令变成可长期依赖的工作流。macFUSEGui 位于 macFUSE 和 <code class=\"font-mono text-sm\">sshfs</code> 之上，提供菜单栏控制、Keychain 凭证、诊断和恢复能力。",
        },
        sections: [
          {
            type: "cards",
            title: "这套技术栈如何配合",
            intro: "把文件系统、传输和编排层分开理解，产品定位会更清晰。",
            cards: [
              { title: "macFUSE", body: "负责把远程路径呈现为 macOS 中的普通目录。" },
              { title: "sshfs", body: "负责通过 SSH 把远程路径挂载到 Finder 和编辑器。" },
              { title: "macFUSEGui", body: "负责保存远程、显示状态、执行恢复、导出诊断，并把两者串成稳定流程。" },
            ],
            columns: 3,
          },
          {
            type: "copy",
            title: "为什么用 GUI，而不是直接执行 sshfs 命令？",
            paragraphs: ["一次性挂载时命令行足够，但当你要管理多个远程、频繁切换网络、合上笔记本或排查失败时，GUI 能减少大量重复操作。"],
            bullets: [
              "按远程独立连接和断开，而不是反复拼命令。",
              "密码放在 Keychain，而不是 shell 历史记录。",
              "在睡眠、唤醒、网络恢复和外部卸载后自动恢复。",
              "挂载失败时可以直接复制诊断信息。",
            ],
          },
          {
            type: "copy",
            title: "安装前提与首次启动",
            paragraphs: [
              "先安装 macFUSE 与 sshfs，再根据 <code class=\"font-mono text-sm\">uname -m</code> 选择 Apple Silicon 或 Intel 构建。",
              "公开构建目前未签名也未 notarize。首次启动时请在 Finder 中右键打开应用，必要时到“系统设置 > 隐私与安全性”中授权。",
            ],
            code: "brew install --cask macFUSE\nbrew install gromgit/fuse/sshfs-mac\n\nuname -m",
          },
          {
            type: "copy",
            title: "日常使用路径",
            ordered: [
              "保存远程的主机、用户名、认证方式、远程路径和本地挂载点。",
              "先在应用里测试连接，再依赖 Finder 或编辑器中的挂载路径。",
              "连接远程后开始工作，让应用负责睡眠、唤醒和网络恢复。",
            ],
          },
          {
            type: "copy",
            title: "什么时候查看故障排查指南",
            paragraphs: ["当首次启动授权已经完成但仍无法挂载、认证信息看起来正确却始终连接不上，或者系统事件后出现陈旧挂载时，就应该打开故障排查页面。"],
            actions: [
              { kind: "page", pageId: "troubleshooting", style: "primary", labelKey: "openTroubleshooting" },
              { kind: "page", pageId: "sshfs", style: "secondary", labelKey: "compareWorkflows" },
            ],
          },
        ],
      },
      sshfs: {
        cardTitle: "Mac 上的 SSHFS GUI",
        cardDescription: "比较 GUI 优先的 SSHFS 工作流与纯命令行方式在 macOS 上的差异。",
        title: "SSHFS GUI for Mac | 使用 macFUSEGui 管理 SSHFS 挂载",
        metaDescription:
          "了解 SSHFS GUI 在 Mac 上能解决什么问题、macFUSEGui 与纯命令行工作流有何区别，以及何时应优先选择 Finder 挂载。",
        hero: {
          eyebrow: "工作流指南",
          lead:
            "<strong>SSHFS GUI for Mac</strong> 的核心价值，是把远程挂载变成你每天都能信任的流程。你不必反复重建命令，而是可以从菜单栏连接远程、查看健康状态，并快速在 Finder 或编辑器里重新打开。",
        },
        sections: [
          {
            type: "copy",
            title: "SSHFS GUI 在 macOS 上解决什么问题",
            paragraphs: ["命令行 SSHFS 适合一次性挂载，但当你有多个主机、需要固定挂载点，或在睡眠和 Wi‑Fi 变化后失去信心时，GUI 会更可靠。"],
            bullets: [
              "无需解析终端输出就能看到挂载健康度。",
              "保存的远程减少重复输入和复制错误。",
              "凭证留在 Keychain，而不是零散脚本里。",
              "一旦挂载，Finder 与编辑器都像使用本地目录一样工作。",
            ],
          },
          {
            type: "cards",
            title: "CLI-only SSHFS 与 GUI-first SSHFS",
            intro: "Shell 很灵活，但 GUI-first 路径能去掉大量重复的运维动作。",
            cards: [
              { title: "CLI-only SSHFS", body: "适合脚本化和一次性操作，但你需要自己处理重试、状态确认、挂载点清理和日志判断。" },
              { title: "GUI-first SSHFS", body: "适合需要保存远程、明确状态、恢复逻辑、诊断输出和稳定 Finder 体验的场景。" },
            ],
            columns: 2,
          },
          {
            type: "copy",
            title: "Finder 挂载目录与 SFTP 客户端的区别",
            paragraphs: ["SFTP 客户端更偏向文件传输，而挂载后的 SSHFS 目录更适合本地式工具链，例如 Finder 预览、编辑器索引和标准文件夹工作流。"],
          },
          {
            type: "copy",
            title: "macFUSEGui 在哪里发挥作用",
            paragraphs: ["macFUSEGui 位于 macFUSE 与 sshfs 之上，专注于按远程管理生命周期、保存凭证、在系统事件后恢复，以及在失败时给出诊断。"],
            actions: [
              { kind: "page", pageId: "install", style: "primary", labelKey: "openInstallGuide" },
              { kind: "page", pageId: "troubleshooting", style: "secondary", labelKey: "openTroubleshooting" },
            ],
          },
        ],
      },
      install: {
        cardTitle: "在 Mac 上安装 macFUSE 与 SSHFS",
        cardDescription: "从前置依赖到第一个可用挂载，快速完成 macFUSEGui 上手。",
        title: "在 Mac 上安装 macFUSE 与 SSHFS | macFUSEGui 指南",
        metaDescription:
          "在 Mac 上安装 macFUSE 与 SSHFS，选择正确的 macFUSEGui 构建，完成首次启动授权，并尽快得到稳定的远程挂载。",
        hero: {
          eyebrow: "安装指南",
          lead:
            "这页适合需要最快路径的用户：先安装 <strong>macFUSE</strong> 和 <strong>SSHFS</strong>，再选择正确构建，完成首次启动授权，然后测试你的第一个远程。",
        },
        sections: [
          {
            type: "copy",
            title: "步骤 1：安装前置依赖",
            paragraphs: ["先安装 macFUSE，再安装 sshfs。macFUSEGui 依赖这两者提供底层文件系统与传输能力。"],
            code: "brew install --cask macFUSE\nbrew install gromgit/fuse/sshfs-mac",
          },
          {
            type: "copy",
            title: "步骤 2：选择正确构建",
            paragraphs: [
              "运行 <code class=\"font-mono text-sm\">uname -m</code> 确认 CPU 架构。<code class=\"font-mono text-sm\">arm64</code> 使用 Apple Silicon 构建，<code class=\"font-mono text-sm\">x86_64</code> 使用 Intel 构建。",
              "下载错误架构的 DMG，是最常见、也最容易避免的安装错误之一。",
            ],
            code: "uname -m",
          },
          {
            type: "copy",
            title: "步骤 3：完成首次启动授权",
            paragraphs: [
              "公开构建目前未签名也未 notarize。请在 Finder 中右键或 Control‑click 应用并选择“打开”。",
              "如果系统仍阻止应用，请前往“系统设置 > 隐私与安全性”批准后重试。",
            ],
          },
          {
            type: "copy",
            title: "步骤 4：添加第一个远程",
            ordered: [
              "填写主机、用户名、认证方式、远程路径和本地挂载点。",
              "在依赖 Finder 之前，先在应用中测试连接。",
              "连接远程后，在 Finder 或编辑器中打开挂载路径。",
            ],
          },
          {
            type: "copy",
            title: "步骤 5：如果安装失败",
            bullets: [
              "重新确认 macFUSE 与 sshfs 是否已正确安装。",
              "确认你下载的是当前机器对应的构建。",
              "检查首次启动授权是否已完成。",
              "认证、挂载点或重连问题请转到故障排查页面。",
            ],
            actions: [
              { kind: "page", pageId: "troubleshooting", style: "primary", labelKey: "openTroubleshooting" },
              { kind: "page", pageId: "product", style: "secondary" },
            ],
          },
        ],
      },
      troubleshooting: {
        cardTitle: "macFUSEGui 故障排查",
        cardDescription: "排查安装、认证、挂载点和恢复流程中的常见问题。",
        title: "macFUSEGui 故障排查 | 修复 Mac 上的 SSHFS 挂载问题",
        metaDescription:
          "在 macOS 上排查 macFUSEGui 问题，包括首次启动授权、认证错误、SSHFS 陈旧挂载、挂载点冲突和重连失败。",
        hero: {
          eyebrow: "支持指南",
          lead:
            "当挂载拒绝连接、睡眠后远程变成陈旧状态，或者 macOS 阻止应用启动时，请用这页把问题定位到依赖、认证、挂载状态或恢复逻辑中的某一层。",
        },
        sections: [
          {
            type: "copy",
            title: "1. 前置依赖失败",
            paragraphs: ["如果应用无法挂载任何内容，先确认 macFUSE 和 sshfs 都已安装。这两者负责真正的文件系统与传输工作。"],
            code: "brew install --cask macFUSE\nbrew install gromgit/fuse/sshfs-mac",
          },
          {
            type: "copy",
            title: "2. 首次启动授权问题",
            paragraphs: [
              "未签名的公开构建需要一次性授权。如果应用弹一下就消失或看起来被阻止，请在 Finder 中右键打开它。",
              "然后检查“系统设置 > 隐私与安全性”里是否有批准入口。",
            ],
          },
          {
            type: "copy",
            title: "3. 认证与主机信息问题",
            bullets: [
              "确认主机名、用户名和远程路径没有填错。",
              "不要假设旧的保存远程仍然对应当前服务器，请在应用里重新测试凭证。",
              "如果密码来自粘贴，请重新保存一次，避免剪贴板带来的隐藏错误。",
            ],
          },
          {
            type: "copy",
            title: "4. 挂载点冲突",
            paragraphs: ["SSH 连接健康并不代表一定能挂载成功。如果本地挂载点与其他远程冲突，或指向陈旧路径，挂载仍会失败。每个远程都应使用唯一的本地目录。"],
          },
          {
            type: "copy",
            title: "5. 睡眠、唤醒与网络恢复问题",
            paragraphs: [
              "macFUSEGui 会尝试在睡眠、唤醒和网络恢复后重新保持期望连接的远程。如果某个远程持续陈旧，先断开它，确认网络确实恢复，再重新连接。",
              "如果问题反复出现，请复制诊断信息，确认具体失败在哪个恢复阶段。",
            ],
          },
          {
            type: "copy",
            title: "6. 陈旧或损坏的挂载",
            paragraphs: ["如果 Finder 仍显示远程，但路径不再响应，请把它视为陈旧挂载。优先从应用里断开，不要在陈旧挂载仍存在时直接删除远程。"],
          },
          {
            type: "copy",
            title: "7. 在猜测之前先看诊断",
            paragraphs: ["诊断快照的目标就是减少盲猜。遇到重复失败时，复制环境检查、远程状态以及最近的挂载或恢复事件。"],
            actions: [
              { kind: "page", pageId: "product", style: "primary", labelKey: "backToProductGuide" },
              { kind: "page", pageId: "sshfs", style: "secondary", labelKey: "compareWorkflows" },
            ],
          },
        ],
      },
    },
  },
  ja: {
    pages: {
      home: {
        cardTitle: "macOS 向け macFUSE GUI",
        cardDescription: "macFUSEGui で macOS にネイティブな SSHFS ワークフローを始める入口です。",
        title: "macFUSE GUI for macOS | SSHFS マウント管理アプリ",
        metaDescription:
          "macOS で macFUSE GUI を使って SSHFS マウントを管理し、メニューバー操作、Keychain 保護、再接続回復、Apple Silicon と Intel 向けダウンロードをまとめて扱えます。",
        structuredDescription:
          "macOS 向けの macFUSE GUI。macFUSE、sshfs、ネイティブなメニューバー体験で SSHFS マウントを管理します。",
        hero: {
          eyebrow: "ネイティブ macOS マウントマネージャー",
          titleTop: "macFUSE GUI SSHFS",
          titleBottom: "for macOS.",
          lead:
            "壊れやすいマウントコマンドを何度も組み立てる必要はありません。macFUSEGui は macOS 向けの macFUSE GUI として、SSHFS 用のリモート単位の操作、Keychain 管理の資格情報、診断、スリープやネットワーク変更後の回復をまとめて提供します。",
          supporting:
            "まず検索意図に合うガイドを選び、次に正しいビルドをダウンロードして、Apple Silicon と Intel の導入を再現可能な手順にそろえてください。",
        },
        heroSpotlight: {
          versionFallback: "最新",
          title: "状態、回復、macOS ネイティブの操作で SSHFS マウントを管理。",
          bullets: [
            "各リモートを個別に接続・切断できます。",
            "認証情報はコピーした秘密情報ではなく Keychain で管理されます。",
            "スリープ、復帰、Wi-Fi の変化、古いアンマウント状態のあとも回復できます。",
            "マウント失敗をエスカレーションする前に診断情報をコピーできます。",
          ],
        },
        guideSection: {
          title: "検索意図に合うガイドを選ぶ",
          intro:
            "このサイトは実際の作業順に整理されています。製品の理解、SSHFS GUI ワークフローの比較、最短インストール、そして失敗したマウントの切り分けです。",
        },
        benefitsSection: {
          title: "macFUSEGui が選ばれる理由",
          intro:
            "macFUSEGui は macFUSE と sshfs の上に位置し、リモートフォルダを Finder やエディタでローカルに近い感覚で扱えるようにします。",
          cards: [
            { title: "すばやいセットアップ", body: "リモートを一度保存すれば、UI から接続テストでき、長い SSHFS コマンドを何度も貼り直す必要がありません。" },
            { title: "自動再接続", body: "スリープ、復帰、Wi‑Fi 変更、外部アンマウント後も必要なリモートを回復できます。" },
            { title: "Keychain 保護", body: "パスワードは macOS Keychain に保存され、非機密の設定だけが JSON に残ります。" },
            { title: "リモート単位の制御", body: "ほかの接続を止めずに、特定のリモートだけ接続や切断ができます。" },
            { title: "診断スナップショット", body: "推測の前に、環境チェック、状態、直近ログをまとめてコピーできます。" },
            { title: "エディタ連携", body: "マウント済みフォルダを Finder やエディタプラグイン経由ですぐ開けます。" },
          ],
        },
        installSection: {
          title: "インストールから初回起動まで",
          intro:
            "最初に macFUSE と sshfs を導入し、次に CPU に合うビルドを選び、最後に macOS の初回承認を完了させます。",
          methodsTitle: "インストール方法",
          methods: [
            {
              title: "Homebrew Cask",
              body: "再現性のあるインストールと更新経路が欲しい場合に最適です。",
              code: "brew tap ripplethor/macfusegui https://github.com/ripplethor/macfuseGUI && brew install --cask ripplethor/macfusegui/macfusegui",
            },
            {
              title: "ターミナルインストーラ",
              body: "最新リリースのインストーラスクリプトを取得し、この Mac に合う成果物を選ばせます。",
              code: '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/ripplethor/macfuseGUI/main/scripts/install_release.sh)"',
            },
            {
              title: "手動 DMG",
              body: "自分の Mac に合う DMG をダウンロードして Applications にドラッグします。",
            },
          ],
          prerequisitesTitle: "前提条件",
          prerequisitesParagraphs: [
            "macFUSEGui は macFUSE や sshfs を置き換えるものではなく、それらを管理するレイヤーです。安定した SSHFS マウントには両方の導入が必要です。",
            "すでに Homebrew core の formula を使っている環境なら、macFUSE の後に <code class=\"font-mono text-sm\">brew install sshfs</code> を試すこともできます。",
          ],
          downloadTitle: "正しいダウンロードを選ぶ",
          downloadParagraphs: [
            "Apple Silicon は <code class=\"font-mono text-sm\">arm64</code>、Intel は <code class=\"font-mono text-sm\">x86_64</code> です。まずアーキテクチャを確認してください。",
            "リリースページでは、<code class=\"font-mono text-sm\">-macos-arm64.dmg</code> または <code class=\"font-mono text-sm\">-macos-x86_64.dmg</code> で終わる DMG を選びます。",
          ],
          checklistTitle: "初回起動チェックリスト",
          checklist: [
            { title: "インストール方法を決める", body: "Homebrew、ワンライナー、DMG のどれを使うかを、更新方法に合わせて選びます。" },
            { title: "Finder から一度開く", body: "Finder で右クリックして「開く」を選び、初回承認を macOS に記録させます。" },
            { title: "「プライバシーとセキュリティ」で承認", body: "まだブロックされる場合は、システム設定の該当画面から許可します。" },
          ],
        },
        howItWorks: {
          title: "仕組み",
          intro:
            "macFUSEGui は制御レイヤーです。macFUSE がファイルシステム、sshfs が転送を担当し、その上でアプリが接続、回復、診断を扱います。",
          points: [
            "安全なマウントコマンドを組み立て、接続・切断・回復を管理します。",
            "パスワードをシェル履歴ではなく macOS Keychain に保存します。",
            "非機密の設定は <code class=\"font-mono text-sm\">~/Library/Application Support/macfuseGui/remotes.json</code> に保存されます。",
            "インストール、認証、回復の失敗時にコピー可能な診断を出力します。",
          ],
        },
        faq: {
          title: "FAQ",
          intro: "セットアップ、セキュリティ、安定性、そして macFUSE GUI と素の SSHFS コマンドの違いを短く確認できます。",
          items: [
            { question: "macFUSE と sshfs は今も必要ですか？", answer: "はい。macFUSEGui は UX と制御のレイヤーで、実際のファイルシステムと転送は macFUSE と sshfs に依存します。" },
            { question: "複数のリモートを同時に管理できますか？", answer: "できます。各リモートは独立した状態と操作を持つので、個別に接続・切断・監視できます。" },
            { question: "パスワードはどこに保存されますか？", answer: "パスワードは macOS Keychain に保存され、JSON には非機密の設定だけが残ります。" },
            { question: "スリープやネットワーク変更の後はどうなりますか？", answer: "必要なリモートは再確認され、ウェイク、到達性の変化、外部アンマウント後に制御された形で再接続されます。" },
            { question: "Finder やコードエディタから開けますか？", answer: "はい。接続後のパスは通常のフォルダのように扱え、エディタプラグイン経由でも開けます。" },
            { question: "初回起動がブロックされたら？", answer: "Finder から一度「開く」を実行し、必要なら「システム設定 > プライバシーとセキュリティ」で承認してください。" },
          ],
        },
      },
      product: {
        cardTitle: "macOS 向け macFUSE GUI",
        cardDescription: "macFUSEGui が macFUSE と sshfs の上で何を担うのかを把握できます。",
        title: "macFUSE GUI for macOS | macFUSEGui の導入と使い方",
        metaDescription:
          "macOS で macFUSE GUI が何をするのか、macFUSEGui が macFUSE と SSHFS とどう連携するのか、そして安定したリモートマウントのための導入手順を確認できます。",
        hero: {
          eyebrow: "製品ガイド",
          lead:
            "<strong>macFUSE GUI</strong> は、単発の SSHFS マウントを日常運用できるワークフローに変えます。macFUSEGui は macFUSE と <code class=\"font-mono text-sm\">sshfs</code> の上で、メニューバー操作、Keychain 管理の資格情報、診断、回復を提供します。",
        },
        sections: [
          {
            type: "cards",
            title: "このスタックの役割分担",
            intro: "ファイルシステム、転送、運用レイヤーを分けて理解すると、製品の位置づけが明確になります。",
            cards: [
              { title: "macFUSE", body: "リモートパスを macOS 上の通常ディレクトリとして見せるファイルシステム層です。" },
              { title: "sshfs", body: "SSH ベースでリモートパスを Finder やエディタへマウントする転送層です。" },
              { title: "macFUSEGui", body: "保存済みリモート、状態表示、回復、診断、エディタ連携をまとめて提供します。" },
            ],
            columns: 3,
          },
          {
            type: "copy",
            title: "なぜ GUI を使うのか",
            paragraphs: ["単発のマウントならシェルでも十分ですが、複数のリモートやネットワーク変更、ノート PC の開閉が絡むと、GUI の方が運用しやすくなります。"],
            bullets: [
              "リモート単位の接続と切断をすぐに実行できる。",
              "パスワードを Keychain に置ける。",
              "スリープ、復帰、ネットワーク復旧後の回復を任せられる。",
              "失敗時に診断をコピーして原因を詰められる。",
            ],
          },
          {
            type: "copy",
            title: "前提条件と初回起動",
            paragraphs: [
              "macFUSE と sshfs を導入し、<code class=\"font-mono text-sm\">uname -m</code> で Apple Silicon か Intel かを確認して正しいビルドを選びます。",
              "公開ビルドは現在未署名のため、初回起動時は Finder から右クリックで開き、必要に応じて「プライバシーとセキュリティ」で承認します。",
            ],
            code: "brew install --cask macFUSE\nbrew install gromgit/fuse/sshfs-mac\n\nuname -m",
          },
          {
            type: "copy",
            title: "日々の使い方",
            ordered: [
              "ホスト、ユーザー名、認証方式、リモートパス、本地マウントポイントを保存する。",
              "Finder やエディタに頼る前に、アプリ内で接続テストを行う。",
              "接続後に作業を始め、スリープやネットワーク復旧の処理はアプリに任せる。",
            ],
          },
          {
            type: "copy",
            title: "トラブルシューティングを見るタイミング",
            paragraphs: ["初回承認が終わってもマウントできない、認証情報が正しいはずなのにつながらない、スリープ後に stale mount になるといった場合はトラブルシューティングを開いてください。"],
            actions: [
              { kind: "page", pageId: "troubleshooting", style: "primary", labelKey: "openTroubleshooting" },
              { kind: "page", pageId: "sshfs", style: "secondary", labelKey: "compareWorkflows" },
            ],
          },
        ],
      },
      sshfs: {
        cardTitle: "Mac 向け SSHFS GUI",
        cardDescription: "GUI 優先の SSHFS ワークフローと CLI-only の違いを macOS 上で比較します。",
        title: "SSHFS GUI for Mac | macFUSEGui で SSHFS マウントを管理",
        metaDescription:
          "Mac 向け SSHFS GUI が解決する課題、macFUSEGui と CLI-only ワークフローの違い、Finder マウントが有利になる場面を確認できます。",
        hero: {
          eyebrow: "ワークフローガイド",
          lead:
            "<strong>SSHFS GUI for Mac</strong> の価値は、リモートマウントを毎日信頼できる流れに変えることです。長いコマンドを作り直す代わりに、メニューバーから接続し、状態を確認し、Finder やエディタで素早く開き直せます。",
        },
        sections: [
          {
            type: "copy",
            title: "SSHFS GUI が解決すること",
            paragraphs: ["CLI の SSHFS は一度きりのマウントなら十分ですが、複数ホストや固定マウントポイント、スリープ復帰後の再確認が必要になると GUI の価値が大きくなります。"],
            bullets: [
              "ターミナル出力を読まなくても状態が見える。",
              "保存済みリモートで入力ミスを減らせる。",
              "資格情報を Keychain に寄せられる。",
              "マウント後は Finder やエディタをローカルのように使える。",
            ],
          },
          {
            type: "cards",
            title: "CLI-only SSHFS と GUI-first SSHFS",
            intro: "シェルは柔軟ですが、GUI-first の方が繰り返しの運用作業を減らせます。",
            cards: [
              { title: "CLI-only SSHFS", body: "スクリプト化には強い一方で、再試行、状態確認、マウントポイントの整理、ログ判断を自分で担う必要があります。" },
              { title: "GUI-first SSHFS", body: "保存済みリモート、明確な状態表示、回復ロジック、診断、Finder 連携が必要な場合に向いています。" },
            ],
            columns: 2,
          },
          {
            type: "copy",
            title: "Finder マウントと SFTP クライアントの違い",
            paragraphs: ["SFTP クライアントは転送向きですが、SSHFS のマウントは Finder プレビュー、エディタのインデックス、通常のフォルダ中心ワークフローに向いています。"],
          },
          {
            type: "copy",
            title: "macFUSEGui の役割",
            paragraphs: ["macFUSEGui は macFUSE と sshfs の上で、リモート単位のライフサイクル管理、資格情報保存、システムイベント後の回復、失敗時の診断を担当します。"],
            actions: [
              { kind: "page", pageId: "install", style: "primary", labelKey: "openInstallGuide" },
              { kind: "page", pageId: "troubleshooting", style: "secondary", labelKey: "openTroubleshooting" },
            ],
          },
        ],
      },
      install: {
        cardTitle: "Mac で macFUSE と SSHFS をインストール",
        cardDescription: "前提条件から最初の実用的なマウントまで、macFUSEGui の導入を最短で進めます。",
        title: "Mac で macFUSE と SSHFS をインストール | macFUSEGui ガイド",
        metaDescription:
          "Mac で macFUSE と SSHFS をインストールし、正しい macFUSEGui ビルドを選び、初回起動の承認を完了して、最初の安定したリモートマウントまで進みます。",
        hero: {
          eyebrow: "インストールガイド",
          lead:
            "このページは最短導入向けです。<strong>macFUSE</strong> と <strong>SSHFS</strong> を入れ、正しいビルドを選び、初回承認を済ませて、最初のリモートをテストします。",
        },
        sections: [
          {
            type: "copy",
            title: "ステップ 1: 前提条件をインストール",
            paragraphs: ["最初に macFUSE、次に sshfs をインストールします。macFUSEGui は両方に依存しています。"],
            code: "brew install --cask macFUSE\nbrew install gromgit/fuse/sshfs-mac",
          },
          {
            type: "copy",
            title: "ステップ 2: 正しいビルドを選ぶ",
            paragraphs: [
              "<code class=\"font-mono text-sm\">uname -m</code> で CPU アーキテクチャを確認します。<code class=\"font-mono text-sm\">arm64</code> は Apple Silicon、<code class=\"font-mono text-sm\">x86_64</code> は Intel です。",
              "別のマシンからリンクを受け取った場合は、間違ったビルドを落としやすいので注意してください。",
            ],
            code: "uname -m",
          },
          {
            type: "copy",
            title: "ステップ 3: 初回起動の承認を完了",
            paragraphs: [
              "現在の公開ビルドは未署名です。Finder で右クリックして「開く」を選びます。",
              "まだブロックされる場合は「システム設定 > プライバシーとセキュリティ」で許可してください。",
            ],
          },
          {
            type: "copy",
            title: "ステップ 4: 最初のリモートを追加",
            ordered: [
              "ホスト、ユーザー名、認証方式、リモートパス、ローカルマウントポイントを入力する。",
              "Finder に頼る前に UI から接続テストを行う。",
              "接続後に Finder またはエディタでマウントパスを開く。",
            ],
          },
          {
            type: "copy",
            title: "ステップ 5: うまくいかないとき",
            bullets: [
              "macFUSE と sshfs が両方インストールされているか再確認する。",
              "自分の Mac に合うビルドを選んだか確認する。",
              "初回承認が完了しているかを確かめる。",
              "認証や再接続の問題はトラブルシューティングへ進む。",
            ],
            actions: [
              { kind: "page", pageId: "troubleshooting", style: "primary", labelKey: "openTroubleshooting" },
              { kind: "page", pageId: "product", style: "secondary" },
            ],
          },
        ],
      },
      troubleshooting: {
        cardTitle: "macFUSEGui トラブルシューティング",
        cardDescription: "インストール、認証、マウントポイント、回復に関する典型的な問題を切り分けます。",
        title: "macFUSEGui トラブルシューティング | Mac の SSHFS マウント問題を修正",
        metaDescription:
          "macOS 上の macFUSEGui 問題を解決します。初回起動の承認、認証エラー、SSHFS の stale mount、マウントポイント競合、再接続失敗に対応します。",
        hero: {
          eyebrow: "サポートガイド",
          lead:
            "マウントがつながらない、スリープ後にリモートが stale になる、macOS がアプリをブロックするといった場合は、このページで前提条件、認証、マウント状態、回復処理のどこが崩れているかを絞り込みます。",
        },
        sections: [
          {
            type: "copy",
            title: "1. 前提条件の失敗",
            paragraphs: ["何もマウントできない場合は、まず macFUSE と sshfs が両方入っているかを確認してください。実際のファイルシステムと転送はこの 2 つに依存します。"],
            code: "brew install --cask macFUSE\nbrew install gromgit/fuse/sshfs-mac",
          },
          {
            type: "copy",
            title: "2. 初回起動の承認問題",
            paragraphs: [
              "未署名ビルドは一度だけ承認が必要です。アプリが一瞬で消える、または起動できない場合は Finder から右クリックで開いてください。",
              "その後、「システム設定 > プライバシーとセキュリティ」に承認導線が出ていないか確認します。",
            ],
          },
          {
            type: "copy",
            title: "3. 認証とホスト情報の問題",
            bullets: [
              "ホスト名、ユーザー名、リモートパスが正しいか確認する。",
              "保存済みリモートを信用しすぎず、アプリから資格情報を再テストする。",
              "貼り付けたパスワードが怪しい場合は一度きれいに保存し直す。",
            ],
          },
          {
            type: "copy",
            title: "4. マウントポイントの衝突",
            paragraphs: ["SSH 接続が成功しても、ローカルマウントポイントが別のリモートと衝突したり stale path を指したりすると失敗します。各リモートに固有のローカルパスを使ってください。"],
          },
          {
            type: "copy",
            title: "5. スリープ、復帰、ネットワーク回復の問題",
            paragraphs: [
              "macFUSEGui は必要なリモートをスリープ、復帰、ネットワーク回復後に戻す設計です。stale のままなら、一度切断してからネットワークが本当に戻っているか確認し、再接続します。",
              "繰り返す場合は診断をコピーし、回復のどの段階が失敗したかを確認してください。",
            ],
          },
          {
            type: "copy",
            title: "6. stale mount / broken mount",
            paragraphs: ["Finder にリモートが見えていてもパスが応答しない場合は stale mount として扱います。まずアプリから切断し、stale mount が残ったまま設定を消さないでください。"],
          },
          {
            type: "copy",
            title: "7. 推測の前に診断を見る",
            paragraphs: ["診断スナップショットは推測を減らすためにあります。繰り返し失敗する場合は、環境、状態、直近の回復イベントを一度に確認できる形でコピーしてください。"],
            actions: [
              { kind: "page", pageId: "product", style: "primary", labelKey: "backToProductGuide" },
              { kind: "page", pageId: "sshfs", style: "secondary", labelKey: "compareWorkflows" },
            ],
          },
        ],
      },
    },
  },
  de: {
    pages: {
      home: {
        cardTitle: "macFUSE GUI für macOS",
        cardDescription: "Hier beginnt der native SSHFS-Workflow auf dem Mac mit macFUSEGui.",
        title: "macFUSE GUI für macOS | SSHFS-Mount-Manager",
        metaDescription:
          "Nutzen Sie macFUSE GUI auf macOS, um SSHFS-Mounts mit Menüleisten-Steuerung, Keychain-Schutz, Wiederverbindung und Downloads für Apple Silicon oder Intel zu verwalten.",
        structuredDescription:
          "macFUSE GUI für macOS zur Verwaltung von SSHFS-Mounts mit macFUSE, sshfs und einer nativen Menüleisten-Oberfläche.",
        hero: {
          eyebrow: "Nativer macOS-Mount-Manager",
          titleTop: "macFUSE GUI SSHFS",
          titleBottom: "for macOS.",
          lead:
            "Keine fragilen Mount-Kommandos mehr neu zusammensetzen. macFUSEGui bietet Teams auf macOS eine fokussierte macFUSE GUI für SSHFS mit Remote-spezifischen Aktionen, Keychain-gesicherten Zugangsdaten, Diagnosen und Wiederherstellung nach Sleep oder Netzwerkwechseln.",
          supporting:
            "Wählen Sie zuerst den passenden Leitfaden, laden Sie dann den richtigen Build herunter und halten Sie Apple-Silicon- und Intel-Installationen auf einem sauberen, wiederholbaren Pfad.",
        },
        heroSpotlight: {
          versionFallback: "aktuell",
          title: "SSHFS-Mounts mit Status, Wiederherstellung und macOS-nativer Steuerung.",
          bullets: [
            "Jedes Remote kann unabhängig verbunden und getrennt werden.",
            "Keychain-gestützte Zugangsdaten statt kopierter Geheimnisse.",
            "Wiederherstellung nach Ruhezustand, Aufwachen, WLAN-Wechseln und veralteten Unmounts.",
            "Diagnosen zum Kopieren, bevor Sie einen Mount-Fehler eskalieren.",
          ],
        },
        guideSection: {
          title: "Wählen Sie den Leitfaden für Ihre Suchabsicht",
          intro:
            "Die Inhalte sind nach realen Aufgaben sortiert: Produkt verstehen, SSHFS-GUI-Workflows vergleichen, schnell installieren und Mount-Fehler gezielt beheben.",
        },
        benefitsSection: {
          title: "Warum Teams macFUSEGui einsetzen",
          intro:
            "Die App sitzt über macFUSE und sshfs, damit entfernte Ordner in Finder, Editoren und täglichen Workflows wie lokale Verzeichnisse wirken.",
          cards: [
            { title: "Schnelles Setup", body: "Remotes einmal speichern, Verbindungen in der UI testen und keine langen SSHFS-Befehle mehr herumkopieren." },
            { title: "Automatische Wiederverbindung", body: "Gewünschte Remotes werden nach Sleep, Wake, WLAN-Wechseln und externen Unmounts wiederhergestellt." },
            { title: "Keychain-Sicherheit", body: "Passwörter bleiben im macOS-Schlüsselbund, während nicht geheime Remote-Daten in JSON gespeichert werden." },
            { title: "Steuerung pro Remote", body: "Einzelne Mounts verbinden oder trennen, ohne andere aktive Remotes zu blockieren." },
            { title: "Diagnosen", body: "Umgebungschecks, Status und letzte Logs kopieren, bevor Sie raten." },
            { title: "Editor-Übergabe", body: "Gemountete Ordner lassen sich direkt in Finder und Editor-Workflows öffnen." },
          ],
        },
        installSection: {
          title: "Installation und erster Start",
          intro:
            "Installieren Sie zuerst macFUSE und sshfs, wählen Sie dann den passenden Build für Ihre CPU und schließen Sie die einmalige macOS-Freigabe ab.",
          methodsTitle: "Installationswege",
          methods: [
            {
              title: "Homebrew Cask",
              body: "Gut für wiederholbare Installationen und Updates.",
              code: "brew tap ripplethor/macfusegui https://github.com/ripplethor/macfuseGUI && brew install --cask ripplethor/macfusegui/macfusegui",
            },
            {
              title: "Terminal-Installer",
              body: "Lädt den neuesten Installer und wählt das passende Artefakt für diesen Mac.",
              code: '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/ripplethor/macfuseGUI/main/scripts/install_release.sh)"',
            },
            {
              title: "Manuelle DMG",
              body: "Laden Sie die richtige DMG für Ihren Mac und ziehen Sie die App nach Applications.",
            },
          ],
          prerequisitesTitle: "Voraussetzungen",
          prerequisitesParagraphs: [
            "macFUSEGui ersetzt macFUSE oder sshfs nicht, sondern verwaltet sie. Für stabile SSHFS-Mounts auf macOS müssen beide installiert sein.",
            "Wenn Ihr Setup bereits die Homebrew-Core-Variante nutzt, können Sie nach macFUSE auch <code class=\"font-mono text-sm\">brew install sshfs</code> testen.",
          ],
          downloadTitle: "Den richtigen Download wählen",
          downloadParagraphs: [
            "Apple Silicon nutzt <code class=\"font-mono text-sm\">arm64</code>, Intel nutzt <code class=\"font-mono text-sm\">x86_64</code>. Prüfen Sie die Architektur zuerst.",
            "Auf der Release-Seite wählen Sie die DMG mit <code class=\"font-mono text-sm\">-macos-arm64.dmg</code> oder <code class=\"font-mono text-sm\">-macos-x86_64.dmg</code>.",
          ],
          checklistTitle: "Checkliste für den ersten Start",
          checklist: [
            { title: "Installationsweg festlegen", body: "Entscheiden Sie je nach Update- und Automatisierungsbedarf zwischen Homebrew, Einzeiler oder direkter DMG." },
            { title: "Einmal aus Finder öffnen", body: "Öffnen Sie die App einmal per Rechtsklick im Finder, damit macOS die Erstfreigabe registriert." },
            { title: "In Datenschutz & Sicherheit freigeben", body: "Wenn macOS weiter blockiert, erlauben Sie die App in den Systemeinstellungen." },
          ],
        },
        howItWorks: {
          title: "So funktioniert es",
          intro:
            "macFUSEGui ist die Steuerungsebene. macFUSE liefert das Dateisystem, sshfs die Übertragung und die App kümmert sich um Verbindung, Wiederherstellung und Diagnose.",
          points: [
            "Baut sichere Mount-Kommandos und verwaltet Verbinden, Trennen und Recovery.",
            "Speichert Passwörter im macOS-Schlüsselbund statt in der Shell-History.",
            "Legt nicht geheime Einstellungen in <code class=\"font-mono text-sm\">~/Library/Application Support/macfuseGui/remotes.json</code> ab.",
            "Liefert kopierbare Diagnosen bei Installations-, Auth- oder Recovery-Fehlern.",
          ],
        },
        faq: {
          title: "FAQ",
          intro: "Kurze Antworten zu Setup, Sicherheit, Zuverlässigkeit und dem Unterschied zwischen einer macFUSE GUI und rohen SSHFS-Befehlen.",
          items: [
            { question: "Brauche ich weiterhin macFUSE und sshfs?", answer: "Ja. macFUSEGui ist die UX- und Steuerungsschicht; Dateisystem und Transport kommen weiterhin von macFUSE und sshfs." },
            { question: "Kann ich mehrere Remotes gleichzeitig verwalten?", answer: "Ja. Jeder Remote hat seinen eigenen Status und eigene Aktionen, sodass Sie Verbindungen unabhängig steuern können." },
            { question: "Wo werden Passwörter gespeichert?", answer: "Passwörter landen im macOS-Schlüsselbund. Die JSON-Datei speichert nur nicht geheime Remote-Einstellungen." },
            { question: "Was passiert nach Sleep oder Netzwerkwechsel?", answer: "Gewünschte Remotes werden nach Wake, Erreichbarkeitswechseln und externen Unmounts kontrolliert neu verbunden." },
            { question: "Kann ich gemountete Pfade in Finder und Editoren öffnen?", answer: "Ja. Nach erfolgreicher Verbindung verhalten sich die Pfade wie normale Ordner und lassen sich direkt weiterreichen." },
            { question: "Was tun, wenn der erste Start blockiert wird?", answer: "Öffnen Sie die App einmal aus Finder per Rechtsklick und geben Sie sie bei Bedarf in Datenschutz & Sicherheit frei." },
          ],
        },
      },
      product: {
        cardTitle: "macFUSE GUI für macOS",
        cardDescription: "Verstehen Sie, wie macFUSEGui über macFUSE und sshfs einzuordnen ist.",
        title: "macFUSE GUI für macOS | macFUSEGui installieren und nutzen",
        metaDescription:
          "Erfahren Sie, was eine macFUSE GUI unter macOS leistet, wie macFUSEGui mit macFUSE und SSHFS zusammenarbeitet und wie Sie stabile Remote-Mounts einrichten.",
        hero: {
          eyebrow: "Produktleitfaden",
          lead:
            "Eine <strong>macFUSE GUI</strong> macht SSHFS auf macOS alltagstauglich. macFUSEGui sitzt über macFUSE und <code class=\"font-mono text-sm\">sshfs</code> und ergänzt Menüleisten-Steuerung, Keychain-Speicherung, Diagnosen und Recovery.",
        },
        sections: [
          {
            type: "cards",
            title: "Wie der Stack zusammenspielt",
            intro: "Wenn Sie Dateisystem, Transport und Orchestrierung trennen, wird die Rolle der App klarer.",
            cards: [
              { title: "macFUSE", body: "Stellt die Dateisystemschicht bereit, damit entfernte Inhalte wie normale macOS-Ordner erscheinen." },
              { title: "sshfs", body: "Übernimmt die SSH-basierte Übertragung für Mounts in Finder und Editor." },
              { title: "macFUSEGui", body: "Liefert gespeicherte Remotes, Status, Recovery, Diagnosen und Editor-Übergabe." },
            ],
            columns: 3,
          },
          {
            type: "copy",
            title: "Warum eine GUI statt roher sshfs-Befehle?",
            paragraphs: ["Für einen einzelnen Mount reicht die Shell. Sobald mehrere Remotes, Netzwechsel oder Suspend/Resume ins Spiel kommen, spart eine GUI deutlich Aufwand."],
            bullets: [
              "Verbinden und trennen pro Remote statt Befehle neu zu bauen.",
              "Keychain statt kopierter Geheimnisse in der Shell-History.",
              "Recovery nach Sleep, Wake, Netzwerk-Wiederkehr und externen Unmounts.",
              "Diagnosen statt Vermutungen, wenn ein Mount hängt.",
            ],
          },
          {
            type: "copy",
            title: "Voraussetzungen und erster Start",
            paragraphs: [
              "Installieren Sie macFUSE und sshfs und wählen Sie anhand von <code class=\"font-mono text-sm\">uname -m</code> den passenden Apple-Silicon- oder Intel-Build.",
              "Öffentliche Builds sind aktuell unsigniert. Öffnen Sie die App deshalb einmal per Rechtsklick aus Finder und geben Sie sie falls nötig in Datenschutz & Sicherheit frei.",
            ],
            code: "brew install --cask macFUSE\nbrew install gromgit/fuse/sshfs-mac\n\nuname -m",
          },
          {
            type: "copy",
            title: "Täglicher Ablauf",
            ordered: [
              "Remote mit Host, Benutzer, Auth-Modus, Remote-Pfad und lokalem Mount-Punkt speichern.",
              "Verbindung in der App testen, bevor Finder oder Editor darauf aufbauen.",
              "Mount verbinden und Recovery bei Sleep oder Netzwechsel der App überlassen.",
            ],
          },
          {
            type: "copy",
            title: "Wann der Troubleshooting-Leitfaden hilft",
            paragraphs: ["Öffnen Sie den Troubleshooting-Leitfaden, wenn die Erstfreigabe erledigt ist, aber Mounts trotzdem scheitern, oder wenn vormals gesunde Remotes nach Systemereignissen nicht mehr reagieren."],
            actions: [
              { kind: "page", pageId: "troubleshooting", style: "primary", labelKey: "openTroubleshooting" },
              { kind: "page", pageId: "sshfs", style: "secondary", labelKey: "compareWorkflows" },
            ],
          },
        ],
      },
      sshfs: {
        cardTitle: "SSHFS GUI für Mac",
        cardDescription: "Vergleichen Sie GUI-first-SSHFS auf macOS mit einem reinen CLI-Ansatz.",
        title: "SSHFS GUI für Mac | SSHFS-Mounts mit macFUSEGui verwalten",
        metaDescription:
          "Sehen Sie, welche Probleme eine SSHFS GUI auf dem Mac löst, wie macFUSEGui sich von einem reinen CLI-Workflow unterscheidet und wann Finder-Mounts sinnvoller sind.",
        hero: {
          eyebrow: "Workflow-Leitfaden",
          lead:
            "Eine <strong>SSHFS GUI für Mac</strong> macht aus Remote-Mounts einen verlässlichen täglichen Workflow. Statt lange Kommandos neu zu bauen, verbinden Sie Remotes per Menüleiste, sehen deren Zustand und öffnen sie schnell in Finder oder Editor.",
        },
        sections: [
          {
            type: "copy",
            title: "Was eine SSHFS GUI auf macOS löst",
            paragraphs: ["CLI-SSHFS ist für Einzelaktionen okay. Mit mehreren Hosts, festen Mount-Punkten und wiederholten Sleep-/Netzwechseln gewinnt die GUI an Wert."],
            bullets: [
              "Mount-Status ist sichtbar, ohne Terminal-Ausgaben zu lesen.",
              "Gespeicherte Remotes reduzieren Tipparbeit und Copy/Paste-Fehler.",
              "Zugangsdaten bleiben im Schlüsselbund statt in Skripten.",
              "Finder und Editor arbeiten wie mit lokalen Ordnern, sobald der Mount steht.",
            ],
          },
          {
            type: "cards",
            title: "CLI-only SSHFS vs. GUI-first SSHFS",
            intro: "Die Shell bleibt flexibel, aber GUI-first spart viel wiederkehrende Betriebsarbeit.",
            cards: [
              { title: "CLI-only SSHFS", body: "Gut für Skripte, aber Sie verwalten Retries, Status, Mount-Punkt-Hygiene und Fehlersuche selbst." },
              { title: "GUI-first SSHFS", body: "Besser, wenn Sie gespeicherte Remotes, klare Zustände, Recovery und Diagnosen brauchen." },
            ],
            columns: 2,
          },
          {
            type: "copy",
            title: "Finder-Mounts vs. SFTP-Clients",
            paragraphs: ["SFTP-Clients eignen sich für gelegentliche Transfers. Ein SSHFS-Mount ist besser, wenn lokale Werkzeuge wie Finder-Vorschau oder Editor-Indexierung im Vordergrund stehen."],
          },
          {
            type: "copy",
            title: "Wo macFUSEGui hineinpasst",
            paragraphs: ["macFUSEGui ist die Steuerungsebene über macFUSE und sshfs. Die App kümmert sich um Lifecycle, Credential-Speicherung, Recovery nach Systemereignissen und Diagnosen."],
            actions: [
              { kind: "page", pageId: "install", style: "primary", labelKey: "openInstallGuide" },
              { kind: "page", pageId: "troubleshooting", style: "secondary", labelKey: "openTroubleshooting" },
            ],
          },
        ],
      },
      install: {
        cardTitle: "macFUSE und SSHFS auf dem Mac installieren",
        cardDescription: "Vom Setup bis zum ersten brauchbaren Mount in macFUSEGui.",
        title: "macFUSE und SSHFS auf dem Mac installieren | macFUSEGui-Leitfaden",
        metaDescription:
          "Installieren Sie macFUSE und SSHFS auf dem Mac, wählen Sie den richtigen macFUSEGui-Build, schließen Sie die Erstfreigabe ab und kommen Sie schnell zu einem stabilen Remote-Mount.",
        hero: {
          eyebrow: "Installationsleitfaden",
          lead:
            "Diese Seite ist für den schnellsten Weg gedacht: <strong>macFUSE</strong> und <strong>SSHFS</strong> installieren, den richtigen Build wählen, die Erstfreigabe abschließen und den ersten Remote testen.",
        },
        sections: [
          { type: "copy", title: "Schritt 1: Voraussetzungen installieren", paragraphs: ["Installieren Sie zuerst macFUSE, dann sshfs. macFUSEGui hängt für Dateisystem und Transport von beiden ab."], code: "brew install --cask macFUSE\nbrew install gromgit/fuse/sshfs-mac" },
          { type: "copy", title: "Schritt 2: Den richtigen Build wählen", paragraphs: ["Mit <code class=\"font-mono text-sm\">uname -m</code> prüfen Sie die Architektur. <code class=\"font-mono text-sm\">arm64</code> steht für Apple Silicon, <code class=\"font-mono text-sm\">x86_64</code> für Intel.", "Ein falscher Download ist einer der häufigsten vermeidbaren Installationsfehler."], code: "uname -m" },
          { type: "copy", title: "Schritt 3: Erstfreigabe abschließen", paragraphs: ["Öffnen Sie den unsignierten Build einmal per Rechtsklick aus Finder.", "Falls macOS weiter blockiert, erlauben Sie die App in Datenschutz & Sicherheit."] },
          { type: "copy", title: "Schritt 4: Ersten Remote hinzufügen", ordered: ["Host, Benutzer, Auth-Modus, Remote-Pfad und lokalen Mount-Punkt eintragen.", "Verbindung in der UI testen.", "Gemounteten Pfad in Finder oder Editor öffnen."] },
          { type: "copy", title: "Schritt 5: Wenn es nicht funktioniert", bullets: ["Prüfen Sie noch einmal, ob macFUSE und sshfs installiert sind.", "Stellen Sie sicher, dass Sie den richtigen Build geladen haben.", "Kontrollieren Sie die Erstfreigabe.", "Wechseln Sie bei Auth-, Recovery- oder Mount-Punkt-Problemen zum Troubleshooting."], actions: [{ kind: "page", pageId: "troubleshooting", style: "primary", labelKey: "openTroubleshooting" }, { kind: "page", pageId: "product", style: "secondary" }] },
        ],
      },
      troubleshooting: {
        cardTitle: "macFUSEGui Fehlerbehebung",
        cardDescription: "Grenzen Sie Installations-, Auth-, Mount-Point- und Recovery-Probleme ein.",
        title: "macFUSEGui Fehlerbehebung | SSHFS-Mount-Probleme auf dem Mac lösen",
        metaDescription:
          "Beheben Sie macFUSEGui-Probleme unter macOS, darunter Erstfreigabe, Authentifizierungsfehler, stale SSHFS-Mounts, Mount-Point-Konflikte und fehlgeschlagene Wiederverbindungen.",
        hero: {
          eyebrow: "Support-Leitfaden",
          lead:
            "Wenn ein Mount nicht verbindet, nach Sleep stale wird oder macOS die App blockiert, hilft diese Seite dabei, Fehlerquellen bei Voraussetzungen, Authentifizierung, Mount-Status und Recovery einzugrenzen.",
        },
        sections: [
          { type: "copy", title: "1. Fehler bei Voraussetzungen", paragraphs: ["Wenn gar nichts mountet, prüfen Sie zuerst, ob macFUSE und sshfs installiert sind. Beide sind für Dateisystem und Transport nötig."], code: "brew install --cask macFUSE\nbrew install gromgit/fuse/sshfs-mac" },
          { type: "copy", title: "2. Probleme bei der Erstfreigabe", paragraphs: ["Unsigne Builds benötigen eine einmalige Freigabe. Öffnen Sie die App per Rechtsklick aus Finder.", "Prüfen Sie anschließend Datenschutz & Sicherheit auf einen Freigabehinweis."] },
          { type: "copy", title: "3. Authentifizierungs- und Host-Probleme", bullets: ["Hostname, Benutzername und Remote-Pfad kontrollieren.", "Anmeldedaten in der App erneut testen.", "Eingefügte Passwörter bei Verdacht sauber neu speichern."] },
          { type: "copy", title: "4. Mount-Point-Konflikte", paragraphs: ["Selbst bei funktionierender SSH-Verbindung kann der Mount scheitern, wenn der lokale Pfad bereits belegt ist oder auf einen stale Mount zeigt. Verwenden Sie eindeutige lokale Verzeichnisse."] },
          { type: "copy", title: "5. Sleep-, Wake- und Netzwerk-Recovery", paragraphs: ["macFUSEGui versucht gewünschte Remotes nach Sleep, Wake und Netzwerk-Rückkehr wiederherzustellen. Bleibt ein Remote stale, trennen Sie ihn, prüfen Sie die Strecke und verbinden Sie erneut.", "Wenn es wiederholt passiert, kopieren Sie Diagnosen und sehen Sie nach, in welcher Recovery-Phase es klemmt."] },
          { type: "copy", title: "6. Stale oder defekte Mounts", paragraphs: ["Wenn Finder den Remote noch zeigt, der Pfad aber nicht reagiert, behandeln Sie ihn als stale Mount. Zuerst in der App trennen, nicht den Remote löschen, solange der stale Mount noch existiert."] },
          { type: "copy", title: "7. Diagnosen vor Vermutungen", paragraphs: ["Der Diagnose-Snapshot reduziert Rätselraten. Kopieren Sie Umgebungschecks, Status und letzte Recovery-Ereignisse, bevor Sie eskalieren."], actions: [{ kind: "page", pageId: "product", style: "primary", labelKey: "backToProductGuide" }, { kind: "page", pageId: "sshfs", style: "secondary", labelKey: "compareWorkflows" }] },
        ],
      },
    },
  },
  fr: {
    pages: {
      home: {
        cardTitle: "macFUSE GUI pour macOS",
        cardDescription: "Point de départ pour un workflow SSHFS natif sur macOS avec macFUSEGui.",
        title: "macFUSE GUI pour macOS | Gestionnaire de montages SSHFS",
        metaDescription:
          "Utilisez macFUSE GUI sur macOS pour gérer les montages SSHFS avec contrôle depuis la barre de menus, sécurité Keychain, reprise après coupure et téléchargements Apple Silicon ou Intel.",
        structuredDescription:
          "macFUSE GUI pour macOS afin de gérer les montages SSHFS avec macFUSE, sshfs et une expérience native dans la barre de menus.",
        hero: {
          eyebrow: "Gestionnaire de montages natif pour macOS",
          titleTop: "macFUSE GUI SSHFS",
          titleBottom: "for macOS.",
          lead:
            "Plus besoin de reconstruire sans cesse des commandes de montage fragiles. macFUSEGui fournit une macFUSE GUI dédiée à SSHFS sur macOS, avec des contrôles par remote, des identifiants dans Keychain, des diagnostics et une reprise après veille ou changement réseau.",
          supporting:
            "Choisissez d'abord le guide qui correspond à votre intention, puis téléchargez la bonne build pour garder une installation propre sur Apple Silicon comme sur Intel.",
        },
        heroSpotlight: {
          versionFallback: "dernière",
          title: "Des montages SSHFS avec état, récupération et contrôles natifs pour macOS.",
          bullets: [
            "Connexion et déconnexion indépendantes pour chaque accès distant.",
            "Identifiants protégés par le Trousseau plutôt que secrets copiés.",
            "Récupération après veille, sortie de veille, changements de Wi-Fi et démontages obsolètes.",
            "Diagnostics copiables avant d'escalader un échec de montage.",
          ],
        },
        guideSection: {
          title: "Choisir le guide adapté à votre recherche",
          intro:
            "Le site suit les vrais cas d'usage : comprendre le produit, comparer les workflows SSHFS GUI, installer rapidement et diagnostiquer un montage qui échoue.",
        },
        benefitsSection: {
          title: "Pourquoi les équipes choisissent macFUSEGui",
          intro:
            "L'application s'appuie sur macFUSE et sshfs pour que les dossiers distants se comportent comme des répertoires macOS normaux dans Finder et vos éditeurs.",
          cards: [
            { title: "Mise en route rapide", body: "Enregistrez un remote une fois, testez la connexion dans l'UI et évitez les longues commandes SSHFS recopiées." },
            { title: "Reconnexion automatique", body: "Les remotes voulus reviennent après veille, réveil, changement de Wi‑Fi et unmount externe." },
            { title: "Sécurité Keychain", body: "Les mots de passe restent dans le trousseau macOS, tandis que la configuration non sensible reste en JSON." },
            { title: "Contrôle par remote", body: "Connectez ou déconnectez un mount sans bloquer les autres remotes actifs." },
            { title: "Diagnostics", body: "Copiez les vérifications d'environnement, les états et les logs récents avant de supposer." },
            { title: "Passage vers l'éditeur", body: "Les dossiers montés s'ouvrent facilement dans Finder et dans le flux plugin des éditeurs." },
          ],
        },
        installSection: {
          title: "Parcours d'installation et premier lancement",
          intro:
            "Installez d'abord macFUSE et sshfs, choisissez ensuite la build adaptée à votre CPU, puis terminez l'autorisation macOS au premier lancement.",
          methodsTitle: "Méthodes d'installation",
          methods: [
            { title: "Homebrew Cask", body: "Idéal pour une installation et des mises à jour répétables.", code: "brew tap ripplethor/macfusegui https://github.com/ripplethor/macfuseGUI && brew install --cask ripplethor/macfusegui/macfusegui" },
            { title: "Installeur Terminal", body: "Récupère l'installeur le plus récent et choisit l'artefact adapté à cette machine.", code: '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/ripplethor/macfuseGUI/main/scripts/install_release.sh)"' },
            { title: "DMG manuel", body: "Téléchargez le bon DMG pour votre Mac puis glissez l'app dans Applications." },
          ],
          prerequisitesTitle: "Prérequis",
          prerequisitesParagraphs: [
            "macFUSEGui ne remplace pas macFUSE ni sshfs, il les orchestre. Pour un montage SSHFS fiable sur macOS, les deux doivent être installés.",
            "Si votre environnement utilise déjà la formule Homebrew core, vous pouvez aussi essayer <code class=\"font-mono text-sm\">brew install sshfs</code> après macFUSE.",
          ],
          downloadTitle: "Choisir le bon téléchargement",
          downloadParagraphs: [
            "Apple Silicon utilise <code class=\"font-mono text-sm\">arm64</code>, Intel utilise <code class=\"font-mono text-sm\">x86_64</code>. Vérifiez l'architecture avant de télécharger.",
            "Sur la page des releases, choisissez le DMG qui se termine par <code class=\"font-mono text-sm\">-macos-arm64.dmg</code> ou <code class=\"font-mono text-sm\">-macos-x86_64.dmg</code>.",
          ],
          checklistTitle: "Checklist du premier lancement",
          checklist: [
            { title: "Choisir une méthode", body: "Sélectionnez Homebrew, le script ou le DMG selon votre besoin d'automatisation." },
            { title: "Ouvrir une fois depuis Finder", body: "Utilisez le clic droit dans Finder pour que macOS enregistre l'autorisation initiale." },
            { title: "Autoriser dans Confidentialité et sécurité", body: "Si macOS bloque encore, autorisez l'app dans les réglages système." },
          ],
        },
        howItWorks: {
          title: "Fonctionnement",
          intro:
            "macFUSEGui est la couche de contrôle. macFUSE fournit le système de fichiers, sshfs le transport, et l'application orchestre la connexion, la reprise et les diagnostics.",
          points: [
            "Construit des commandes de montage sûres et gère connexion, déconnexion et recovery.",
            "Stocke les mots de passe dans le trousseau macOS au lieu de l'historique shell.",
            "Conserve la configuration non sensible dans <code class=\"font-mono text-sm\">~/Library/Application Support/macfuseGui/remotes.json</code>.",
            "Expose des diagnostics copiables quand l'installation, l'authentification ou la reprise échouent.",
          ],
        },
        faq: {
          title: "FAQ",
          intro: "Réponses rapides sur le setup, la sécurité, la fiabilité et la différence entre une macFUSE GUI et des commandes SSHFS brutes.",
          items: [
            { question: "Faut-il toujours installer macFUSE et sshfs ?", answer: "Oui. macFUSEGui est la couche UX et de contrôle, mais le système de fichiers et le transport viennent toujours de macFUSE et sshfs." },
            { question: "Puis-je gérer plusieurs remotes en même temps ?", answer: "Oui. Chaque remote a son propre état et ses propres actions." },
            { question: "Où sont stockés les mots de passe ?", answer: "Dans le trousseau macOS. Le JSON ne contient que les réglages non sensibles." },
            { question: "Que se passe-t-il après veille ou changement réseau ?", answer: "Les remotes désirés sont revérifiés et reconnectés après réveil, changement de connectivité ou unmount externe." },
            { question: "Puis-je ouvrir les chemins montés dans Finder et mon éditeur ?", answer: "Oui. Une fois montés, ils se comportent comme des dossiers normaux." },
            { question: "Que faire si le premier lancement est bloqué ?", answer: "Ouvrez l'app une fois depuis Finder via clic droit, puis autorisez-la si nécessaire dans Confidentialité et sécurité." },
          ],
        },
      },
      product: {
        cardTitle: "macFUSE GUI pour macOS",
        cardDescription: "Comprendre où se place macFUSEGui au-dessus de macFUSE et sshfs.",
        title: "macFUSE GUI pour macOS | Installer et utiliser macFUSEGui",
        metaDescription:
          "Découvrez ce qu'apporte une macFUSE GUI sur macOS, comment macFUSEGui s'appuie sur macFUSE et SSHFS, et comment obtenir des montages distants fiables.",
        hero: { eyebrow: "Guide produit", lead: "Une <strong>macFUSE GUI</strong> rend SSHFS praticable au quotidien sur macOS. macFUSEGui s'appuie sur macFUSE et <code class=\"font-mono text-sm\">sshfs</code> pour ajouter contrôle dans la barre de menus, identifiants Keychain, diagnostics et reprise." },
        sections: [
          { type: "cards", title: "Comment la pile s'assemble", intro: "Séparer système de fichiers, transport et orchestration aide à voir le rôle du produit.", cards: [{ title: "macFUSE", body: "Fournit la couche système de fichiers qui fait apparaître un chemin distant comme un dossier macOS ordinaire." }, { title: "sshfs", body: "Assure le transport SSH pour monter un chemin distant dans Finder et vos éditeurs." }, { title: "macFUSEGui", body: "Ajoute remotes sauvegardés, état, recovery, diagnostics et ouverture dans l'éditeur." }], columns: 3 },
          { type: "copy", title: "Pourquoi une GUI plutôt que des commandes sshfs ?", paragraphs: ["Le shell suffit pour un montage ponctuel. Dès qu'il faut gérer plusieurs remotes, des changements réseau ou des sorties de veille, une GUI réduit fortement le travail répétitif."], bullets: ["Connexion et déconnexion par remote.", "Stockage Keychain au lieu de secrets recopiés.", "Recovery après veille, réveil et retour réseau.", "Diagnostics copiables quand un mount échoue."] },
          { type: "copy", title: "Prérequis et premier lancement", paragraphs: ["Installez macFUSE et sshfs, puis choisissez la bonne build avec <code class=\"font-mono text-sm\">uname -m</code>.", "Les builds publiques étant non signées, ouvrez une première fois depuis Finder puis autorisez l'app si nécessaire."], code: "brew install --cask macFUSE\nbrew install gromgit/fuse/sshfs-mac\n\nuname -m" },
          { type: "copy", title: "Workflow quotidien", ordered: ["Enregistrer host, utilisateur, mode d'authentification, chemin distant et point de montage local.", "Tester la connexion dans l'app.", "Lancer le mount et laisser l'app gérer les événements système."] },
          { type: "copy", title: "Quand ouvrir le guide de dépannage", paragraphs: ["Ouvrez le dépannage quand l'autorisation initiale est faite mais que les mounts échouent encore, ou quand un remote sain devient stale après un événement système."], actions: [{ kind: "page", pageId: "troubleshooting", style: "primary", labelKey: "openTroubleshooting" }, { kind: "page", pageId: "sshfs", style: "secondary", labelKey: "compareWorkflows" }] },
        ],
      },
      sshfs: {
        cardTitle: "SSHFS GUI pour Mac",
        cardDescription: "Comparer un workflow SSHFS piloté par GUI à une approche purement CLI sur macOS.",
        title: "SSHFS GUI pour Mac | Gérer les montages SSHFS avec macFUSEGui",
        metaDescription:
          "Voyez ce qu'une SSHFS GUI pour Mac résout, comment macFUSEGui se compare à un workflow purement CLI, et quand les montages Finder sont plus utiles que les commandes manuelles.",
        hero: { eyebrow: "Guide workflow", lead: "Une <strong>SSHFS GUI pour Mac</strong> transforme les montages distants en workflow fiable. Au lieu de reconstruire des commandes, vous connectez vos remotes depuis la barre de menus, voyez leur état et les rouvrez rapidement dans Finder ou l'éditeur." },
        sections: [
          { type: "copy", title: "Ce qu'une SSHFS GUI résout sur macOS", paragraphs: ["Le SSHFS en ligne de commande fonctionne pour l'occasionnel. Avec plusieurs hôtes, des points de montage fixes et des sorties de veille, la GUI devient beaucoup plus confortable."], bullets: ["État visible sans lire la sortie terminal.", "Remotes enregistrés pour réduire les erreurs.", "Secrets gardés dans Keychain.", "Finder et éditeurs se comportent comme avec des dossiers locaux."] },
          { type: "cards", title: "SSHFS CLI-only contre GUI-first", intro: "Le shell reste flexible, mais GUI-first supprime beaucoup d'opérations répétitives.", cards: [{ title: "SSHFS CLI-only", body: "Très scriptable, mais vous gérez vous-même retries, état, hygiène des mount points et lecture des erreurs." }, { title: "SSHFS GUI-first", body: "Mieux adapté aux remotes sauvegardés, à l'état clair, à la reprise et aux diagnostics." }], columns: 2 },
          { type: "copy", title: "Montages Finder vs clients SFTP", paragraphs: ["Les clients SFTP sont utiles pour le transfert ponctuel. Un mount SSHFS convient mieux aux workflows fondés sur Finder, l'indexation de l'éditeur et les dossiers standards."] },
          { type: "copy", title: "Où intervient macFUSEGui", paragraphs: ["macFUSEGui est la couche de contrôle au-dessus de macFUSE et sshfs, centrée sur le cycle de vie des remotes, les identifiants, la reprise et les diagnostics."], actions: [{ kind: "page", pageId: "install", style: "primary", labelKey: "openInstallGuide" }, { kind: "page", pageId: "troubleshooting", style: "secondary", labelKey: "openTroubleshooting" }] },
        ],
      },
      install: {
        cardTitle: "Installer macFUSE et SSHFS sur Mac",
        cardDescription: "Aller des prérequis au premier mount utile dans macFUSEGui.",
        title: "Installer macFUSE et SSHFS sur Mac | Guide macFUSEGui",
        metaDescription:
          "Installez macFUSE et SSHFS sur Mac, choisissez la bonne version de macFUSEGui, terminez l'approbation au premier lancement et obtenez rapidement un montage distant fiable.",
        hero: { eyebrow: "Guide d'installation", lead: "Cette page vise le chemin le plus court : installer <strong>macFUSE</strong> et <strong>SSHFS</strong>, choisir la bonne build, terminer l'autorisation initiale et tester le premier remote." },
        sections: [
          { type: "copy", title: "Étape 1 : installer les prérequis", paragraphs: ["Installez d'abord macFUSE puis sshfs. macFUSEGui dépend des deux."], code: "brew install --cask macFUSE\nbrew install gromgit/fuse/sshfs-mac" },
          { type: "copy", title: "Étape 2 : choisir la bonne build", paragraphs: ["Vérifiez l'architecture avec <code class=\"font-mono text-sm\">uname -m</code>. <code class=\"font-mono text-sm\">arm64</code> pour Apple Silicon, <code class=\"font-mono text-sm\">x86_64</code> pour Intel.", "Un mauvais téléchargement est l'une des erreurs d'installation les plus faciles à éviter."], code: "uname -m" },
          { type: "copy", title: "Étape 3 : terminer l'autorisation initiale", paragraphs: ["Ouvrez la build non signée une première fois depuis Finder.", "Si macOS bloque encore, autorisez l'app dans Confidentialité et sécurité."] },
          { type: "copy", title: "Étape 4 : ajouter le premier remote", ordered: ["Renseigner host, utilisateur, mode d'authentification, chemin distant et point de montage local.", "Tester la connexion dans l'UI.", "Ouvrir le chemin monté dans Finder ou l'éditeur."] },
          { type: "copy", title: "Étape 5 : si l'installation échoue", bullets: ["Revérifier macFUSE et sshfs.", "Confirmer la bonne build.", "Vérifier l'autorisation initiale.", "Basculer vers le dépannage pour les problèmes d'auth ou de reprise."], actions: [{ kind: "page", pageId: "troubleshooting", style: "primary", labelKey: "openTroubleshooting" }, { kind: "page", pageId: "product", style: "secondary" }] },
        ],
      },
      troubleshooting: {
        cardTitle: "Dépannage macFUSEGui",
        cardDescription: "Isoler les problèmes d'installation, d'authentification, de mount point et de recovery.",
        title: "Dépannage macFUSEGui | Corriger les problèmes de montage SSHFS sur Mac",
        metaDescription:
          "Corrigez les problèmes macFUSEGui sur macOS : approbation au premier lancement, erreurs d'authentification, montages SSHFS obsolètes, conflits de point de montage et échecs de reconnexion.",
        hero: { eyebrow: "Guide de support", lead: "Si un mount refuse de se connecter, devient stale après la veille, ou si macOS bloque l'app, cette page aide à isoler la cause côté prérequis, authentification, état du mount ou logique de recovery." },
        sections: [
          { type: "copy", title: "1. Échec des prérequis", paragraphs: ["Si rien ne se monte, commencez par vérifier que macFUSE et sshfs sont bien installés."], code: "brew install --cask macFUSE\nbrew install gromgit/fuse/sshfs-mac" },
          { type: "copy", title: "2. Problèmes d'autorisation initiale", paragraphs: ["Les builds non signées demandent une autorisation unique. Ouvrez l'app via clic droit dans Finder.", "Regardez ensuite Confidentialité et sécurité pour l'invite d'approbation."] },
          { type: "copy", title: "3. Problèmes d'authentification et d'hôte", bullets: ["Vérifier hostname, utilisateur et chemin distant.", "Retester les identifiants depuis l'app.", "Réenregistrer un mot de passe collé s'il paraît suspect."] },
          { type: "copy", title: "4. Conflits de point de montage", paragraphs: ["Une connexion SSH peut être valide alors que le mount échoue si le point de montage local est déjà utilisé ou stale. Utilisez un chemin local unique par remote."] },
          { type: "copy", title: "5. Problèmes de veille, réveil et réseau", paragraphs: ["macFUSEGui tente de restaurer les remotes désirés après veille, réveil et retour réseau. Si un remote reste stale, déconnectez-le, vérifiez le chemin réseau puis reconnectez-le.", "Si cela se répète, copiez les diagnostics pour voir quelle phase de recovery échoue."] },
          { type: "copy", title: "6. Montages stale ou cassés", paragraphs: ["Si Finder affiche encore le remote mais que le chemin ne répond plus, traitez-le comme un stale mount. Déconnectez d'abord depuis l'app."] },
          { type: "copy", title: "7. Utiliser les diagnostics avant de deviner", paragraphs: ["Le snapshot de diagnostics existe pour éviter les suppositions. Copiez environnement, état et événements récents avant d'escalader."], actions: [{ kind: "page", pageId: "product", style: "primary", labelKey: "backToProductGuide" }, { kind: "page", pageId: "sshfs", style: "secondary", labelKey: "compareWorkflows" }] },
        ],
      },
    },
  },
  "pt-br": {
    pages: {
      home: {
        cardTitle: "macFUSE GUI para macOS",
        cardDescription: "Ponto de partida para um fluxo SSHFS nativo no macOS com macFUSEGui.",
        title: "macFUSE GUI para macOS | Gerenciador de montagens SSHFS",
        metaDescription:
          "Use macFUSE GUI no macOS para gerenciar montagens SSHFS com controle pela barra de menus, segurança do Keychain, recuperação de reconexão e downloads para Apple Silicon ou Intel.",
        structuredDescription:
          "macFUSE GUI para macOS para gerenciar montagens SSHFS com macFUSE, sshfs e uma experiência nativa na barra de menus.",
        hero: {
          eyebrow: "Gerenciador nativo de mounts no macOS",
          titleTop: "macFUSE GUI SSHFS",
          titleBottom: "for macOS.",
          lead:
            "Pare de remontar comandos frágeis manualmente. O macFUSEGui entrega uma macFUSE GUI focada em SSHFS no macOS, com ações por remote, credenciais no Keychain, diagnósticos e recuperação após sleep ou mudança de rede.",
          supporting:
            "Escolha primeiro o guia certo, depois baixe a build correta e mantenha instalações Apple Silicon e Intel em um fluxo limpo e repetível.",
        },
        heroSpotlight: {
          versionFallback: "mais recente",
          title: "Montagens SSHFS com status, recuperação e controles nativos do macOS.",
          bullets: [
            "Conecte e desconecte cada remote de forma independente.",
            "Credenciais no Keychain em vez de segredos copiados.",
            "Recuperação após suspensão, despertar, mudanças de Wi-Fi e desmontagens obsoletas.",
            "Diagnósticos que você pode copiar antes de escalar uma falha de montagem.",
          ],
        },
        guideSection: {
          title: "Escolha o guia que combina com a sua busca",
          intro:
            "O site está organizado pelos problemas reais: entender o produto, comparar fluxos SSHFS GUI, instalar rápido e investigar mounts que falham.",
        },
        benefitsSection: {
          title: "Por que equipes usam macFUSEGui",
          intro:
            "O app fica acima de macFUSE e sshfs para que pastas remotas se comportem como diretórios locais no Finder e nos editores.",
          cards: [
            { title: "Setup rápido", body: "Salve remotes uma vez, teste a conexão na UI e pare de copiar comandos SSHFS longos." },
            { title: "Reconexão automática", body: "Remotes desejados voltam após sleep, wake, troca de Wi‑Fi e unmount externo." },
            { title: "Segurança com Keychain", body: "Senhas ficam no Keychain do macOS, enquanto a configuração não sensível permanece em JSON." },
            { title: "Controle por remote", body: "Conecte ou desconecte um mount sem bloquear os demais remotes ativos." },
            { title: "Diagnósticos", body: "Copie verificações de ambiente, estados e logs recentes antes de adivinhar." },
            { title: "Handoff para editores", body: "Pastas montadas podem ser abertas no Finder e no fluxo de plugins de editor." },
          ],
        },
        installSection: {
          title: "Instalação e primeiro lançamento",
          intro:
            "Instale macFUSE e sshfs primeiro, escolha a build certa para a sua CPU e conclua a autorização única do macOS.",
          methodsTitle: "Métodos de instalação",
          methods: [
            { title: "Homebrew Cask", body: "Bom para instalações e atualizações repetíveis.", code: "brew tap ripplethor/macfusegui https://github.com/ripplethor/macfuseGUI && brew install --cask ripplethor/macfusegui/macfusegui" },
            { title: "Instalador via Terminal", body: "Busca o instalador mais recente e escolhe o artefato correto para esta máquina.", code: '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/ripplethor/macfuseGUI/main/scripts/install_release.sh)"' },
            { title: "DMG manual", body: "Baixe o DMG certo para o seu Mac e arraste o app para Applications." },
          ],
          prerequisitesTitle: "Pré-requisitos",
          prerequisitesParagraphs: [
            "O macFUSEGui não substitui macFUSE nem sshfs; ele os orquestra. Para mounts SSHFS confiáveis no macOS, os dois precisam estar instalados.",
            "Se o seu ambiente já usa a fórmula do Homebrew core, você também pode testar <code class=\"font-mono text-sm\">brew install sshfs</code> depois do macFUSE.",
          ],
          downloadTitle: "Escolha o download correto",
          downloadParagraphs: [
            "Apple Silicon usa <code class=\"font-mono text-sm\">arm64</code>, Intel usa <code class=\"font-mono text-sm\">x86_64</code>. Verifique a arquitetura antes de baixar.",
            "Na página de releases, escolha o DMG terminado em <code class=\"font-mono text-sm\">-macos-arm64.dmg</code> ou <code class=\"font-mono text-sm\">-macos-x86_64.dmg</code>.",
          ],
          checklistTitle: "Checklist do primeiro lançamento",
          checklist: [
            { title: "Escolher um método", body: "Selecione Homebrew, script ou DMG conforme a necessidade de automação." },
            { title: "Abrir uma vez pelo Finder", body: "Use clique direito no Finder para que o macOS registre a autorização inicial." },
            { title: "Autorizar em Privacidade e Segurança", body: "Se o macOS continuar bloqueando, libere o app nos Ajustes do Sistema." },
          ],
        },
        howItWorks: {
          title: "Como funciona",
          intro:
            "O macFUSEGui é a camada de controle. O macFUSE fornece o sistema de arquivos, o sshfs cuida do transporte e o app gerencia conexão, recuperação e diagnósticos.",
          points: [
            "Monta comandos seguros e gerencia conectar, desconectar e recovery.",
            "Guarda senhas no Keychain do macOS em vez do histórico do shell.",
            "Salva configuração não sensível em <code class=\"font-mono text-sm\">~/Library/Application Support/macfuseGui/remotes.json</code>.",
            "Entrega diagnósticos copiáveis quando instalação, autenticação ou recovery falham.",
          ],
        },
        faq: {
          title: "FAQ",
          intro: "Respostas rápidas sobre setup, segurança, confiabilidade e a diferença entre uma macFUSE GUI e comandos SSHFS puros.",
          items: [
            { question: "Ainda preciso instalar macFUSE e sshfs?", answer: "Sim. O macFUSEGui é a camada de UX e controle; sistema de arquivos e transporte continuam vindo de macFUSE e sshfs." },
            { question: "Posso gerenciar vários remotes ao mesmo tempo?", answer: "Sim. Cada remote tem seu próprio estado e suas próprias ações." },
            { question: "Onde as senhas ficam armazenadas?", answer: "No Keychain do macOS. O JSON guarda apenas configurações não sensíveis." },
            { question: "O que acontece após sleep ou mudança de rede?", answer: "Remotes desejados são rechecados e reconectados após wake, mudança de conectividade e unmount externo." },
            { question: "Posso abrir caminhos montados no Finder e no editor?", answer: "Sim. Depois de montados, eles se comportam como pastas normais." },
            { question: "E se o primeiro lançamento for bloqueado?", answer: "Abra o app uma vez pelo Finder com clique direito e autorize-o se necessário em Privacidade e Segurança." },
          ],
        },
      },
      product: {
        cardTitle: "macFUSE GUI para macOS",
        cardDescription: "Entenda como o macFUSEGui se posiciona acima de macFUSE e sshfs.",
        title: "macFUSE GUI para macOS | Instale e use o macFUSEGui",
        metaDescription:
          "Entenda o que uma macFUSE GUI faz no macOS, como o macFUSEGui funciona com macFUSE e SSHFS e como instalar tudo para obter montagens remotas confiáveis.",
        hero: {
          eyebrow: "Guia do produto",
          lead:
            "Uma <strong>macFUSE GUI</strong> transforma SSHFS em algo sustentável no dia a dia do macOS. O macFUSEGui fica acima de macFUSE e <code class=\"font-mono text-sm\">sshfs</code> e adiciona controle pela barra de menus, credenciais no Keychain, diagnósticos e recovery.",
        },
        sections: [
          { type: "cards", title: "Como a pilha se encaixa", intro: "Separar sistema de arquivos, transporte e orquestração deixa o papel do app mais claro.", cards: [{ title: "macFUSE", body: "Fornece a camada de sistema de arquivos para que o caminho remoto apareça como diretório normal no macOS." }, { title: "sshfs", body: "Cuida do transporte baseado em SSH para montar caminhos remotos no Finder e nos editores." }, { title: "macFUSEGui", body: "Adiciona remotes salvos, estado, recovery, diagnósticos e abertura em editores." }], columns: 3 },
          { type: "copy", title: "Por que usar GUI em vez de comandos sshfs crus?", paragraphs: ["Para um mount isolado, o shell basta. Quando há múltiplos remotes, mudanças de rede e ciclos de sleep/wake, a GUI reduz muito o trabalho repetitivo."], bullets: ["Conectar e desconectar por remote.", "Keychain em vez de segredos copiados no shell.", "Recovery após sleep, wake, retorno de rede e unmount externo.", "Diagnósticos copiáveis quando um mount falha."] },
          { type: "copy", title: "Pré-requisitos e primeiro lançamento", paragraphs: ["Instale macFUSE e sshfs e escolha a build correta com <code class=\"font-mono text-sm\">uname -m</code>.", "Como as builds públicas ainda são não assinadas, abra o app uma vez pelo Finder e autorize-o se necessário."], code: "brew install --cask macFUSE\nbrew install gromgit/fuse/sshfs-mac\n\nuname -m" },
          { type: "copy", title: "Fluxo diário", ordered: ["Salvar host, usuário, modo de autenticação, caminho remoto e ponto de mount local.", "Testar a conexão no app.", "Conectar o remote e deixar o app cuidar dos eventos do sistema."] },
          { type: "copy", title: "Quando abrir o guia de solução de problemas", paragraphs: ["Abra o guia de troubleshooting quando a aprovação inicial estiver concluída mas os mounts ainda falharem, ou quando um remote estável virar stale após um evento do sistema."], actions: [{ kind: "page", pageId: "troubleshooting", style: "primary", labelKey: "openTroubleshooting" }, { kind: "page", pageId: "sshfs", style: "secondary", labelKey: "compareWorkflows" }] },
        ],
      },
      sshfs: {
        cardTitle: "SSHFS GUI para Mac",
        cardDescription: "Compare um fluxo SSHFS guiado por interface com uma abordagem só de linha de comando no macOS.",
        title: "SSHFS GUI para Mac | Gerencie montagens SSHFS com macFUSEGui",
        metaDescription:
          "Veja o que uma SSHFS GUI para Mac resolve, como o macFUSEGui se compara a um fluxo só de CLI e quando montagens no Finder superam comandos manuais de SSHFS.",
        hero: {
          eyebrow: "Guia de workflow",
          lead:
            "Uma <strong>SSHFS GUI para Mac</strong> transforma mounts remotos em um fluxo confiável. Em vez de recriar comandos longos, você conecta remotes pela barra de menus, vê o estado e os reabre rápido no Finder ou no editor.",
        },
        sections: [
          { type: "copy", title: "O que uma SSHFS GUI resolve no macOS", paragraphs: ["SSHFS por linha de comando serve para uso ocasional. Quando entram vários hosts, pontos de mount fixos e ciclos de sleep/wake, a GUI vale muito mais."], bullets: ["Estado visível sem ler a saída do terminal.", "Remotes salvos reduzem digitação e erros.", "Segredos ficam no Keychain.", "Finder e editor funcionam como se fossem pastas locais."] },
          { type: "cards", title: "SSHFS só em CLI vs. SSHFS guiado por GUI", intro: "O shell segue flexível, mas a abordagem GUI-first elimina muito trabalho operacional repetitivo.", cards: [{ title: "SSHFS só em CLI", body: "É forte para scripts, mas você mesmo gerencia retries, estado, higiene do mount point e leitura de erros." }, { title: "SSHFS com GUI", body: "É melhor quando você precisa de remotes salvos, estado claro, recovery e diagnósticos." }], columns: 2 },
          { type: "copy", title: "Montagens no Finder vs. clientes SFTP", paragraphs: ["Clientes SFTP são úteis para transferências pontuais. Um mount SSHFS é melhor quando o fluxo depende do Finder, da indexação do editor e de pastas normais."] },
          { type: "copy", title: "Onde o macFUSEGui entra", paragraphs: ["O macFUSEGui é a camada de controle acima de macFUSE e sshfs, focada em ciclo de vida do remote, credenciais, recovery e diagnósticos."], actions: [{ kind: "page", pageId: "install", style: "primary", labelKey: "openInstallGuide" }, { kind: "page", pageId: "troubleshooting", style: "secondary", labelKey: "openTroubleshooting" }] },
        ],
      },
      install: {
        cardTitle: "Instalar macFUSE e SSHFS no Mac",
        cardDescription: "Saia dos pré-requisitos e chegue ao primeiro mount utilizável no macFUSEGui.",
        title: "Instalar macFUSE e SSHFS no Mac | Guia do macFUSEGui",
        metaDescription:
          "Instale macFUSE e SSHFS no Mac, escolha a build correta do macFUSEGui, conclua a aprovação no primeiro lançamento e chegue ao seu primeiro mount remoto confiável.",
        hero: {
          eyebrow: "Guia de instalação",
          lead:
            "Esta página prioriza o caminho mais curto: instalar <strong>macFUSE</strong> e <strong>SSHFS</strong>, escolher a build certa, concluir a aprovação inicial e testar o primeiro remote.",
        },
        sections: [
          { type: "copy", title: "Passo 1: instalar os pré-requisitos", paragraphs: ["Instale primeiro macFUSE e depois sshfs. O macFUSEGui depende dos dois."], code: "brew install --cask macFUSE\nbrew install gromgit/fuse/sshfs-mac" },
          { type: "copy", title: "Passo 2: escolher a build correta", paragraphs: ["Use <code class=\"font-mono text-sm\">uname -m</code> para confirmar a arquitetura. <code class=\"font-mono text-sm\">arm64</code> é Apple Silicon; <code class=\"font-mono text-sm\">x86_64</code> é Intel.", "Baixar a build errada ainda é um erro comum e evitável."], code: "uname -m" },
          { type: "copy", title: "Passo 3: concluir a aprovação inicial", paragraphs: ["Abra a build não assinada uma vez pelo Finder com clique direito.", "Se o macOS ainda bloquear, autorize o app em Privacidade e Segurança."] },
          { type: "copy", title: "Passo 4: adicionar o primeiro remote", ordered: ["Preencha host, usuário, modo de autenticação, caminho remoto e ponto de mount local.", "Teste a conexão na UI.", "Abra o caminho montado no Finder ou no editor."] },
          { type: "copy", title: "Passo 5: se algo falhar", bullets: ["Confirme novamente macFUSE e sshfs.", "Verifique se a build baixada é a certa.", "Revise a aprovação inicial.", "Use troubleshooting para auth, recovery e problemas de mount point."], actions: [{ kind: "page", pageId: "troubleshooting", style: "primary", labelKey: "openTroubleshooting" }, { kind: "page", pageId: "product", style: "secondary" }] },
        ],
      },
      troubleshooting: {
        cardTitle: "Solução de problemas do macFUSEGui",
        cardDescription: "Isole problemas de instalação, autenticação, mount point e recovery.",
        title: "Solução de problemas do macFUSEGui | Corrija falhas de mount SSHFS no Mac",
        metaDescription:
          "Corrija problemas do macFUSEGui no macOS, incluindo aprovação inicial, erros de autenticação, mounts SSHFS obsoletos, conflitos de ponto de montagem e falhas de reconexão.",
        hero: {
          eyebrow: "Guia de suporte",
          lead:
            "Se um mount não conecta, fica stale depois do sleep ou o macOS bloqueia o app, esta página ajuda a separar a causa entre pré-requisitos, autenticação, estado do mount e recovery.",
        },
        sections: [
          { type: "copy", title: "1. Falhas de pré-requisito", paragraphs: ["Se nada monta, confirme primeiro se macFUSE e sshfs estão instalados."], code: "brew install --cask macFUSE\nbrew install gromgit/fuse/sshfs-mac" },
          { type: "copy", title: "2. Problemas na aprovação inicial", paragraphs: ["Builds não assinadas exigem autorização única. Abra o app pelo Finder com clique direito.", "Depois verifique Privacidade e Segurança para o aviso de aprovação."] },
          { type: "copy", title: "3. Problemas de autenticação e host", bullets: ["Confira hostname, usuário e caminho remoto.", "Reteste as credenciais dentro do app.", "Se a senha foi colada, salve de novo se parecer suspeita."] },
          { type: "copy", title: "4. Conflitos de mount point", paragraphs: ["Mesmo com SSH funcionando, o mount pode falhar se o caminho local já estiver em uso ou apontando para um mount stale. Use caminhos locais únicos."] },
          { type: "copy", title: "5. Problemas após sleep, wake e rede", paragraphs: ["O macFUSEGui tenta restaurar remotes desejados após sleep, wake e retorno da rede. Se um remote continuar stale, desconecte-o, confirme o caminho de rede e conecte novamente.", "Se acontecer sempre, copie os diagnósticos para ver em qual fase do recovery falhou."] },
          { type: "copy", title: "6. Mounts stale ou quebrados", paragraphs: ["Se o Finder ainda mostra o remote, mas o caminho não responde, trate-o como stale mount. Desconecte primeiro no app."] },
          { type: "copy", title: "7. Diagnósticos antes de suposições", paragraphs: ["O snapshot de diagnóstico existe para reduzir chute. Copie ambiente, estado e eventos recentes antes de escalar o problema."], actions: [{ kind: "page", pageId: "product", style: "primary", labelKey: "backToProductGuide" }, { kind: "page", pageId: "sshfs", style: "secondary", labelKey: "compareWorkflows" }] },
        ],
      },
    },
  },
  es: {
    pages: {
      home: {
        cardTitle: "macFUSE GUI para macOS",
        cardDescription: "Punto de partida para un flujo SSHFS nativo en macOS con macFUSEGui.",
        title: "macFUSE GUI para macOS | Gestor de montajes SSHFS",
        metaDescription:
          "Use macFUSE GUI en macOS para gestionar montajes SSHFS con control desde la barra de menús, seguridad de Keychain, recuperación de reconexión y descargas para Apple Silicon o Intel.",
        structuredDescription:
          "macFUSE GUI para macOS para gestionar montajes SSHFS con macFUSE, sshfs y una experiencia nativa en la barra de menús.",
        hero: {
          eyebrow: "Gestor de montajes nativo para macOS",
          titleTop: "macFUSE GUI SSHFS",
          titleBottom: "for macOS.",
          lead:
            "Deja de reconstruir comandos de mount frágiles. macFUSEGui ofrece una macFUSE GUI centrada en SSHFS para macOS, con acciones por remote, credenciales en Keychain, diagnósticos y recuperación tras reposo o cambios de red.",
          supporting:
            "Elige primero la guía adecuada, descarga después la build correcta y mantén Apple Silicon e Intel en un flujo limpio y repetible.",
        },
        heroSpotlight: {
          versionFallback: "última",
          title: "Montajes SSHFS con estado, recuperación y controles nativos de macOS.",
          bullets: [
            "Conexión y desconexión independientes para cada remote.",
            "Credenciales respaldadas por Keychain en lugar de secretos copiados.",
            "Recuperación tras suspensión, reactivación, cambios de Wi-Fi y desmontajes obsoletos.",
            "Diagnósticos que puedes copiar antes de escalar un fallo de montaje.",
          ],
        },
        guideSection: {
          title: "Elige la guía que encaja con tu intención de búsqueda",
          intro:
            "El sitio está organizado alrededor de tareas reales: entender el producto, comparar flujos SSHFS GUI, instalar rápido y diagnosticar mounts que fallan.",
        },
        benefitsSection: {
          title: "Por qué los equipos usan macFUSEGui",
          intro:
            "La app se sitúa sobre macFUSE y sshfs para que las carpetas remotas se comporten como directorios normales de macOS en Finder y editores.",
          cards: [
            { title: "Configuración rápida", body: "Guarda remotes una sola vez, prueba la conexión en la UI y evita copiar comandos SSHFS largos." },
            { title: "Reconexión automática", body: "Los remotes deseados vuelven tras reposo, activación, cambios de Wi‑Fi y desmontajes externos." },
            { title: "Seguridad con Keychain", body: "Las contraseñas permanecen en el llavero de macOS y la configuración no sensible sigue en JSON." },
            { title: "Control por remote", body: "Conecta o desconecta un mount sin bloquear los demás remotes activos." },
            { title: "Diagnósticos", body: "Copia comprobaciones de entorno, estados y logs recientes antes de adivinar." },
            { title: "Paso a editores", body: "Las carpetas montadas se pueden abrir directamente en Finder y en el flujo de plugins de editor." },
          ],
        },
        installSection: {
          title: "Instalación y primer arranque",
          intro:
            "Instala primero macFUSE y sshfs, elige después la build correcta para tu CPU y completa la autorización única de macOS.",
          methodsTitle: "Métodos de instalación",
          methods: [
            { title: "Homebrew Cask", body: "Ideal para instalaciones y actualizaciones repetibles.", code: "brew tap ripplethor/macfusegui https://github.com/ripplethor/macfuseGUI && brew install --cask ripplethor/macfusegui/macfusegui" },
            { title: "Instalador por Terminal", body: "Obtiene el instalador más reciente y elige el artefacto adecuado para esta máquina.", code: '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/ripplethor/macfuseGUI/main/scripts/install_release.sh)"' },
            { title: "DMG manual", body: "Descarga el DMG correcto para tu Mac y arrastra la app a Applications." },
          ],
          prerequisitesTitle: "Requisitos previos",
          prerequisitesParagraphs: [
            "macFUSEGui no sustituye a macFUSE ni a sshfs; los orquesta. Para mounts SSHFS fiables en macOS necesitas ambos instalados.",
            "Si tu entorno ya usa la fórmula de Homebrew core, también puedes probar <code class=\"font-mono text-sm\">brew install sshfs</code> después de macFUSE.",
          ],
          downloadTitle: "Elige la descarga correcta",
          downloadParagraphs: [
            "Apple Silicon usa <code class=\"font-mono text-sm\">arm64</code>; Intel usa <code class=\"font-mono text-sm\">x86_64</code>. Verifica la arquitectura antes de descargar.",
            "En la página de releases, elige el DMG que termina en <code class=\"font-mono text-sm\">-macos-arm64.dmg</code> o <code class=\"font-mono text-sm\">-macos-x86_64.dmg</code>.",
          ],
          checklistTitle: "Checklist del primer arranque",
          checklist: [
            { title: "Elegir un método", body: "Selecciona Homebrew, script o DMG según tu necesidad de automatización." },
            { title: "Abrir una vez desde Finder", body: "Usa clic derecho en Finder para que macOS registre la autorización inicial." },
            { title: "Autorizar en Privacidad y seguridad", body: "Si macOS sigue bloqueando, permite la app en los Ajustes del sistema." },
          ],
        },
        howItWorks: {
          title: "Cómo funciona",
          intro:
            "macFUSEGui es la capa de control. macFUSE aporta el sistema de archivos, sshfs el transporte y la app gestiona conexión, recuperación y diagnósticos.",
          points: [
            "Construye comandos de mount seguros y gestiona conectar, desconectar y recovery.",
            "Guarda contraseñas en el llavero de macOS en vez del historial del shell.",
            "Mantiene la configuración no sensible en <code class=\"font-mono text-sm\">~/Library/Application Support/macfuseGui/remotes.json</code>.",
            "Entrega diagnósticos copiables cuando fallan instalación, autenticación o recovery.",
          ],
        },
        faq: {
          title: "FAQ",
          intro: "Respuestas rápidas sobre setup, seguridad, fiabilidad y la diferencia entre una macFUSE GUI y los comandos SSHFS en bruto.",
          items: [
            { question: "¿Sigo necesitando instalar macFUSE y sshfs?", answer: "Sí. macFUSEGui es la capa de UX y control; el sistema de archivos y el transporte siguen viniendo de macFUSE y sshfs." },
            { question: "¿Puedo gestionar varios remotes a la vez?", answer: "Sí. Cada remote tiene su propio estado y sus propias acciones." },
            { question: "¿Dónde se guardan las contraseñas?", answer: "En el llavero de macOS. El JSON solo guarda configuración no sensible." },
            { question: "¿Qué ocurre tras reposo o cambio de red?", answer: "Los remotes deseados se revalidan y reconectan tras activación, cambios de conectividad y desmontajes externos." },
            { question: "¿Puedo abrir las rutas montadas en Finder y editores?", answer: "Sí. Una vez montadas se comportan como carpetas normales." },
            { question: "¿Y si el primer arranque queda bloqueado?", answer: "Abre la app una vez desde Finder con clic derecho y autorízala si hace falta en Privacidad y seguridad." },
          ],
        },
      },
      product: {
        cardTitle: "macFUSE GUI para macOS",
        cardDescription: "Entiende cómo se sitúa macFUSEGui por encima de macFUSE y sshfs.",
        title: "macFUSE GUI para macOS | Instalar y usar macFUSEGui",
        metaDescription:
          "Descubra qué hace una macFUSE GUI en macOS, cómo macFUSEGui funciona con macFUSE y SSHFS, y cómo instalarlo para obtener montajes remotos fiables.",
        hero: {
          eyebrow: "Guía del producto",
          lead:
            "Una <strong>macFUSE GUI</strong> vuelve SSHFS sostenible en el día a día de macOS. macFUSEGui se apoya en macFUSE y <code class=\"font-mono text-sm\">sshfs</code> y añade control desde la barra de menús, credenciales en Keychain, diagnósticos y recovery.",
        },
        sections: [
          { type: "cards", title: "Cómo encaja la pila", intro: "Separar sistema de archivos, transporte y orquestación ayuda a entender el papel del producto.", cards: [{ title: "macFUSE", body: "Aporta la capa de sistema de archivos para que la ruta remota aparezca como un directorio normal en macOS." }, { title: "sshfs", body: "Gestiona el transporte basado en SSH para montar rutas remotas en Finder y editores." }, { title: "macFUSEGui", body: "Añade remotes guardados, estado, recovery, diagnósticos y apertura en el editor." }], columns: 3 },
          { type: "copy", title: "¿Por qué usar una GUI en vez de comandos sshfs?", paragraphs: ["Para un mount puntual, la shell sirve. Cuando hay varios remotes, cambios de red y ciclos de reposo, una GUI reduce mucho el trabajo repetitivo."], bullets: ["Conectar y desconectar por remote.", "Keychain en lugar de secretos copiados en la shell.", "Recovery tras reposo, activación, vuelta de red y desmontajes externos.", "Diagnósticos copiables cuando un mount falla."] },
          { type: "copy", title: "Requisitos previos y primer arranque", paragraphs: ["Instala macFUSE y sshfs y elige la build correcta con <code class=\"font-mono text-sm\">uname -m</code>.", "Como las builds públicas aún no están firmadas, abre la app una vez desde Finder y autorízala si hace falta."], code: "brew install --cask macFUSE\nbrew install gromgit/fuse/sshfs-mac\n\nuname -m" },
          { type: "copy", title: "Flujo diario", ordered: ["Guardar host, usuario, modo de autenticación, ruta remota y punto de mount local.", "Probar la conexión dentro de la app.", "Conectar el remote y dejar que la app gestione los eventos del sistema."] },
          { type: "copy", title: "Cuándo abrir la guía de solución de problemas", paragraphs: ["Abre troubleshooting cuando la autorización inicial ya está hecha pero los mounts siguen fallando, o cuando un remote sano se vuelve stale tras un evento del sistema."], actions: [{ kind: "page", pageId: "troubleshooting", style: "primary", labelKey: "openTroubleshooting" }, { kind: "page", pageId: "sshfs", style: "secondary", labelKey: "compareWorkflows" }] },
        ],
      },
      sshfs: {
        cardTitle: "SSHFS GUI para Mac",
        cardDescription: "Compara un flujo SSHFS guiado por interfaz con uno solo de CLI en macOS.",
        title: "SSHFS GUI para Mac | Gestiona montajes SSHFS con macFUSEGui",
        metaDescription:
          "Vea qué resuelve una SSHFS GUI en Mac, cómo macFUSEGui se compara con un flujo solo de CLI y cuándo los montajes en Finder son mejores que los comandos manuales.",
        hero: {
          eyebrow: "Guía de workflow",
          lead:
            "Una <strong>SSHFS GUI para Mac</strong> convierte los mounts remotos en un flujo fiable. En lugar de rehacer comandos largos, conectas remotes desde la barra de menús, ves su estado y los reabres rápido en Finder o en el editor.",
        },
        sections: [
          { type: "copy", title: "Qué resuelve una SSHFS GUI en macOS", paragraphs: ["SSHFS por línea de comandos sirve para algo puntual. Cuando aparecen varios hosts, puntos de mount fijos y ciclos de reposo, la GUI aporta mucho más."], bullets: ["Estado visible sin leer la salida del terminal.", "Remotes guardados para reducir errores.", "Secretos en Keychain.", "Finder y editor se comportan como si fueran carpetas locales."] },
          { type: "cards", title: "SSHFS solo CLI vs SSHFS con GUI", intro: "La shell sigue siendo flexible, pero el enfoque GUI-first elimina mucho trabajo operativo repetitivo.", cards: [{ title: "SSHFS solo CLI", body: "Es ideal para scripts, pero tú mismo gestionas retries, estado, higiene del mount point y lectura de errores." }, { title: "SSHFS con GUI", body: "Encaja mejor cuando necesitas remotes guardados, estado claro, recovery y diagnósticos." }], columns: 2 },
          { type: "copy", title: "Montajes en Finder frente a clientes SFTP", paragraphs: ["Los clientes SFTP sirven para transferencias puntuales. Un mount SSHFS es mejor cuando el flujo depende de Finder, la indexación del editor y carpetas normales."] },
          { type: "copy", title: "Dónde encaja macFUSEGui", paragraphs: ["macFUSEGui es la capa de control por encima de macFUSE y sshfs, centrada en el ciclo de vida del remote, las credenciales, el recovery y los diagnósticos."], actions: [{ kind: "page", pageId: "install", style: "primary", labelKey: "openInstallGuide" }, { kind: "page", pageId: "troubleshooting", style: "secondary", labelKey: "openTroubleshooting" }] },
        ],
      },
      install: {
        cardTitle: "Instalar macFUSE y SSHFS en Mac",
        cardDescription: "Pasa de los requisitos previos al primer mount útil en macFUSEGui.",
        title: "Instalar macFUSE y SSHFS en Mac | Guía de macFUSEGui",
        metaDescription:
          "Instale macFUSE y SSHFS en Mac, elija la build correcta de macFUSEGui, complete la aprobación del primer inicio y consiga un montaje remoto fiable cuanto antes.",
        hero: {
          eyebrow: "Guía de instalación",
          lead:
            "Esta página prioriza el camino más corto: instalar <strong>macFUSE</strong> y <strong>SSHFS</strong>, elegir la build correcta, completar la aprobación inicial y probar el primer remote.",
        },
        sections: [
          { type: "copy", title: "Paso 1: instalar los requisitos previos", paragraphs: ["Instala primero macFUSE y después sshfs. macFUSEGui depende de ambos."], code: "brew install --cask macFUSE\nbrew install gromgit/fuse/sshfs-mac" },
          { type: "copy", title: "Paso 2: elegir la build correcta", paragraphs: ["Usa <code class=\"font-mono text-sm\">uname -m</code> para confirmar la arquitectura. <code class=\"font-mono text-sm\">arm64</code> es Apple Silicon; <code class=\"font-mono text-sm\">x86_64</code> es Intel.", "Descargar la build equivocada sigue siendo un error común y evitable."], code: "uname -m" },
          { type: "copy", title: "Paso 3: completar la aprobación inicial", paragraphs: ["Abre una vez la build no firmada desde Finder con clic derecho.", "Si macOS sigue bloqueando, autoriza la app en Privacidad y seguridad."] },
          { type: "copy", title: "Paso 4: añadir el primer remote", ordered: ["Rellenar host, usuario, modo de autenticación, ruta remota y punto de mount local.", "Probar la conexión en la UI.", "Abrir la ruta montada en Finder o en el editor."] },
          { type: "copy", title: "Paso 5: si algo falla", bullets: ["Confirma de nuevo macFUSE y sshfs.", "Verifica que la build descargada es la correcta.", "Revisa la aprobación inicial.", "Usa troubleshooting para auth, recovery y problemas de mount point."], actions: [{ kind: "page", pageId: "troubleshooting", style: "primary", labelKey: "openTroubleshooting" }, { kind: "page", pageId: "product", style: "secondary" }] },
        ],
      },
      troubleshooting: {
        cardTitle: "Solución de problemas de macFUSEGui",
        cardDescription: "Aísla problemas de instalación, autenticación, mount point y recovery.",
        title: "Solución de problemas de macFUSEGui | Corrige fallos de montaje SSHFS en Mac",
        metaDescription:
          "Corrija problemas de macFUSEGui en macOS, incluida la aprobación del primer inicio, errores de autenticación, montajes SSHFS obsoletos, conflictos de punto de montaje y fallos de reconexión.",
        hero: {
          eyebrow: "Guía de soporte",
          lead:
            "Si un mount no conecta, se vuelve stale tras el reposo o macOS bloquea la app, esta página ayuda a separar la causa entre requisitos previos, autenticación, estado del mount y recovery.",
        },
        sections: [
          { type: "copy", title: "1. Fallos de requisitos previos", paragraphs: ["Si no monta nada, confirma primero que macFUSE y sshfs están instalados."], code: "brew install --cask macFUSE\nbrew install gromgit/fuse/sshfs-mac" },
          { type: "copy", title: "2. Problemas en la aprobación inicial", paragraphs: ["Las builds no firmadas requieren una autorización única. Abre la app desde Finder con clic derecho.", "Después revisa Privacidad y seguridad para ver el aviso de aprobación."] },
          { type: "copy", title: "3. Problemas de autenticación y host", bullets: ["Revisa hostname, usuario y ruta remota.", "Vuelve a probar las credenciales desde la app.", "Si la contraseña fue pegada, vuelve a guardarla si parece sospechosa."] },
          { type: "copy", title: "4. Conflictos de mount point", paragraphs: ["Aunque SSH funcione, el mount puede fallar si la ruta local ya está ocupada o apunta a un mount stale. Usa rutas locales únicas."] },
          { type: "copy", title: "5. Problemas tras reposo, activación y red", paragraphs: ["macFUSEGui intenta restaurar los remotes deseados tras reposo, activación y vuelta de red. Si un remote sigue stale, desconéctalo, confirma el camino de red y vuelve a conectarlo.", "Si se repite, copia los diagnósticos para ver en qué fase del recovery falla."] },
          { type: "copy", title: "6. Mounts stale o rotos", paragraphs: ["Si Finder sigue mostrando el remote pero la ruta ya no responde, trátalo como stale mount. Desconecta primero desde la app."] },
          { type: "copy", title: "7. Diagnósticos antes de suposiciones", paragraphs: ["El snapshot de diagnósticos existe para reducir el tanteo. Copia entorno, estado y eventos recientes antes de escalar el problema."], actions: [{ kind: "page", pageId: "product", style: "primary", labelKey: "backToProductGuide" }, { kind: "page", pageId: "sshfs", style: "secondary", labelKey: "compareWorkflows" }] },
        ],
      },
    },
  },
  ko: {
    pages: {
      home: {
        cardTitle: "macOS용 macFUSE GUI",
        cardDescription: "macFUSEGui로 macOS에서 네이티브한 SSHFS 워크플로를 시작하는 출발점입니다.",
        title: "macFUSE GUI for macOS | SSHFS 마운트 관리자 앱",
        metaDescription:
          "macOS에서 macFUSE GUI로 SSHFS 마운트를 관리하고, 메뉴 막대 제어, Keychain 보안, 재연결 복구, Apple Silicon과 Intel용 다운로드를 함께 사용할 수 있습니다.",
        structuredDescription:
          "macFUSE, sshfs, 메뉴 막대 경험을 바탕으로 SSHFS 마운트를 관리하는 macOS용 macFUSE GUI.",
        hero: {
          eyebrow: "macOS 네이티브 마운트 관리자",
          titleTop: "macFUSE GUI SSHFS",
          titleBottom: "for macOS.",
          lead:
            "이제 취약한 마운트 명령을 계속 다시 만들 필요가 없습니다. macFUSEGui는 macOS에서 SSHFS를 위한 macFUSE GUI로서 remote별 제어, Keychain 자격 증명, 진단, 절전 및 네트워크 변경 이후의 복구를 제공합니다.",
          supporting:
            "먼저 검색 의도에 맞는 가이드를 고르고, 다음으로 올바른 빌드를 내려받아 Apple Silicon과 Intel 설치를 반복 가능하게 유지하세요.",
        },
        heroSpotlight: {
          versionFallback: "최신",
          title: "상태, 복구, macOS 네이티브 제어를 갖춘 SSHFS 마운트.",
          bullets: [
            "각 remote를 독립적으로 연결하고 연결 해제할 수 있습니다.",
            "복사된 비밀 정보 대신 Keychain 기반 자격 증명을 사용합니다.",
            "절전, 깨우기, Wi-Fi 변경, 오래된 마운트 해제 뒤에도 복구합니다.",
            "마운트 실패를 상위로 올리기 전에 복사할 수 있는 진단 정보를 제공합니다.",
          ],
        },
        guideSection: {
          title: "검색 의도에 맞는 가이드 선택",
          intro:
            "사이트는 실제 작업 흐름에 맞춰 구성되어 있습니다. 제품 이해, SSHFS GUI 비교, 빠른 설치, 그리고 실패한 마운트의 원인 파악입니다.",
        },
        benefitsSection: {
          title: "팀이 macFUSEGui를 선택하는 이유",
          intro:
            "앱은 macFUSE와 sshfs 위에서 동작해 원격 폴더가 Finder와 편집기에서 로컬 디렉터리처럼 느껴지게 합니다.",
          cards: [
            { title: "빠른 설정", body: "remote를 한 번 저장하면 UI에서 바로 연결 테스트를 할 수 있어 긴 SSHFS 명령을 반복해 복사할 필요가 없습니다." },
            { title: "자동 재연결", body: "원하는 remote는 절전, 깨우기, Wi‑Fi 변경, 외부 unmount 후에도 복구됩니다." },
            { title: "Keychain 보안", body: "비밀번호는 macOS Keychain에 남고, 민감하지 않은 설정만 JSON에 저장됩니다." },
            { title: "remote별 제어", body: "다른 remote를 막지 않고 특정 mount만 연결하거나 끊을 수 있습니다." },
            { title: "진단", body: "추측하기 전에 환경 점검, 상태, 최근 로그를 복사할 수 있습니다." },
            { title: "편집기 연동", body: "마운트된 폴더를 Finder와 편집기 플러그인 흐름에서 바로 열 수 있습니다." },
          ],
        },
        installSection: {
          title: "설치와 첫 실행 경로",
          intro:
            "먼저 macFUSE와 sshfs를 설치하고, CPU에 맞는 빌드를 고른 뒤, macOS의 1회 승인 절차를 마칩니다.",
          methodsTitle: "설치 방법",
          methods: [
            { title: "Homebrew Cask", body: "반복 가능한 설치와 업데이트에 적합합니다.", code: "brew tap ripplethor/macfusegui https://github.com/ripplethor/macfuseGUI && brew install --cask ripplethor/macfusegui/macfusegui" },
            { title: "터미널 설치기", body: "최신 설치 스크립트를 가져와 현재 Mac에 맞는 아티팩트를 선택합니다.", code: '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/ripplethor/macfuseGUI/main/scripts/install_release.sh)"' },
            { title: "수동 DMG", body: "자신의 Mac에 맞는 DMG를 받아 Applications로 옮깁니다." },
          ],
          prerequisitesTitle: "필수 조건",
          prerequisitesParagraphs: [
            "macFUSEGui는 macFUSE나 sshfs를 대체하지 않고 이를 관리합니다. 안정적인 SSHFS 마운트를 위해 두 구성요소 모두 필요합니다.",
            "환경이 Homebrew core 포뮬러를 이미 사용한다면 macFUSE 이후 <code class=\"font-mono text-sm\">brew install sshfs</code> 도 시도할 수 있습니다.",
          ],
          downloadTitle: "올바른 다운로드 선택",
          downloadParagraphs: [
            "Apple Silicon은 <code class=\"font-mono text-sm\">arm64</code>, Intel은 <code class=\"font-mono text-sm\">x86_64</code> 입니다. 다운로드 전에 아키텍처를 확인하세요.",
            "릴리스 페이지에서 <code class=\"font-mono text-sm\">-macos-arm64.dmg</code> 또는 <code class=\"font-mono text-sm\">-macos-x86_64.dmg</code> 로 끝나는 DMG를 고릅니다.",
          ],
          checklistTitle: "첫 실행 체크리스트",
          checklist: [
            { title: "설치 방법 결정", body: "자동화 수준에 따라 Homebrew, 스크립트, DMG 중 하나를 고릅니다." },
            { title: "Finder에서 한 번 열기", body: "Finder에서 우클릭으로 열어 macOS가 초기 승인을 기록하도록 합니다." },
            { title: "개인정보 보호 및 보안에서 허용", body: "계속 차단되면 시스템 설정에서 앱을 허용합니다." },
          ],
        },
        howItWorks: {
          title: "동작 방식",
          intro:
            "macFUSEGui는 제어 계층입니다. macFUSE가 파일 시스템을, sshfs가 전송을 담당하고, 앱은 연결, 복구, 진단을 관리합니다.",
          points: [
            "안전한 마운트 명령을 만들고 연결, 해제, recovery를 관리합니다.",
            "비밀번호를 shell 기록이 아니라 macOS Keychain에 저장합니다.",
            "민감하지 않은 설정은 <code class=\"font-mono text-sm\">~/Library/Application Support/macfuseGui/remotes.json</code> 에 보관합니다.",
            "설치, 인증, recovery 실패 시 복사 가능한 진단을 제공합니다.",
          ],
        },
        faq: {
          title: "FAQ",
          intro: "설정, 보안, 안정성, 그리고 macFUSE GUI와 순수 SSHFS 명령의 차이를 빠르게 확인할 수 있습니다.",
          items: [
            { question: "macFUSE와 sshfs를 여전히 설치해야 하나요?", answer: "예. macFUSEGui는 UX와 제어 계층이며, 실제 파일 시스템과 전송은 macFUSE와 sshfs가 담당합니다." },
            { question: "여러 remote를 동시에 관리할 수 있나요?", answer: "예. 각 remote는 독립된 상태와 동작을 가집니다." },
            { question: "비밀번호는 어디에 저장되나요?", answer: "macOS Keychain에 저장되며 JSON에는 민감하지 않은 설정만 남습니다." },
            { question: "절전이나 네트워크 변경 후에는 어떻게 되나요?", answer: "원하는 remote는 깨우기, 연결성 변경, 외부 unmount 이후 다시 확인되고 재연결됩니다." },
            { question: "마운트된 경로를 Finder와 편집기에서 열 수 있나요?", answer: "예. 마운트가 완료되면 일반 폴더처럼 동작합니다." },
            { question: "첫 실행이 차단되면 어떻게 하나요?", answer: "Finder에서 우클릭으로 한 번 열고, 필요하면 개인정보 보호 및 보안에서 허용하세요." },
          ],
        },
      },
      product: {
        cardTitle: "macOS용 macFUSE GUI",
        cardDescription: "macFUSEGui가 macFUSE와 sshfs 위에서 어떤 역할을 하는지 이해할 수 있습니다.",
        title: "macFUSE GUI for macOS | macFUSEGui 설치 및 사용",
        metaDescription:
          "macOS에서 macFUSE GUI가 무엇을 하는지, macFUSEGui가 macFUSE 및 SSHFS와 어떻게 동작하는지, 그리고 안정적인 원격 마운트를 위해 어떻게 설치하는지 확인할 수 있습니다.",
        hero: {
          eyebrow: "제품 가이드",
          lead:
            "<strong>macFUSE GUI</strong> 는 macOS에서 SSHFS를 일상적으로 운영 가능한 워크플로로 바꿔 줍니다. macFUSEGui는 macFUSE와 <code class=\"font-mono text-sm\">sshfs</code> 위에서 메뉴 막대 제어, Keychain 자격 증명, 진단, recovery를 제공합니다.",
        },
        sections: [
          { type: "cards", title: "스택이 맞물리는 방식", intro: "파일 시스템, 전송, 오케스트레이션을 나눠 보면 앱의 역할이 더 선명해집니다.", cards: [{ title: "macFUSE", body: "원격 경로를 macOS의 일반 디렉터리처럼 보이게 하는 파일 시스템 계층입니다." }, { title: "sshfs", body: "원격 경로를 Finder와 편집기에 마운트하는 SSH 기반 전송 계층입니다." }, { title: "macFUSEGui", body: "저장된 remote, 상태, recovery, 진단, 편집기 열기 흐름을 제공합니다." }], columns: 3 },
          { type: "copy", title: "왜 raw sshfs 명령 대신 GUI를 쓰나요?", paragraphs: ["한 번만 마운트할 때는 셸로 충분하지만, 여러 remote와 네트워크 변경, sleep/wake가 얽히면 GUI가 반복 작업을 크게 줄여 줍니다."], bullets: ["remote별 연결/해제를 빠르게 실행할 수 있습니다.", "비밀 정보가 shell 기록 대신 Keychain에 머뭅니다.", "sleep, wake, 네트워크 복귀 후 recovery를 맡길 수 있습니다.", "mount가 실패할 때 진단을 바로 복사할 수 있습니다."] },
          { type: "copy", title: "필수 조건과 첫 실행", paragraphs: ["macFUSE와 sshfs를 설치한 뒤 <code class=\"font-mono text-sm\">uname -m</code> 으로 Apple Silicon 또는 Intel 빌드를 선택합니다.", "공개 빌드는 현재 서명되지 않았으므로 Finder에서 한 번 열고 필요하면 시스템 설정에서 허용해야 합니다."], code: "brew install --cask macFUSE\nbrew install gromgit/fuse/sshfs-mac\n\nuname -m" },
          { type: "copy", title: "일상적인 사용 흐름", ordered: ["host, 사용자, 인증 방식, 원격 경로, 로컬 mount point를 저장합니다.", "Finder나 편집기보다 먼저 앱에서 연결 테스트를 합니다.", "remote를 연결하고 시스템 이벤트 관리는 앱에 맡깁니다."] },
          { type: "copy", title: "문제 해결 가이드를 볼 때", paragraphs: ["초기 승인은 끝났지만 mount가 계속 실패하거나, 정상 remote가 시스템 이벤트 뒤 stale 상태가 되면 troubleshooting 가이드를 여세요."], actions: [{ kind: "page", pageId: "troubleshooting", style: "primary", labelKey: "openTroubleshooting" }, { kind: "page", pageId: "sshfs", style: "secondary", labelKey: "compareWorkflows" }] },
        ],
      },
      sshfs: {
        cardTitle: "Mac용 SSHFS GUI",
        cardDescription: "GUI 중심 SSHFS 흐름과 CLI-only 접근의 차이를 macOS에서 비교합니다.",
        title: "SSHFS GUI for Mac | macFUSEGui로 SSHFS 마운트 관리",
        metaDescription:
          "Mac용 SSHFS GUI가 해결하는 문제, macFUSEGui와 CLI-only 워크플로의 차이, Finder 마운트가 수동 SSHFS 명령보다 나은 상황을 확인하세요.",
        hero: {
          eyebrow: "워크플로 가이드",
          lead:
            "<strong>SSHFS GUI for Mac</strong> 의 핵심 가치는 원격 마운트를 매일 믿고 쓸 수 있는 흐름으로 바꾸는 데 있습니다. 긴 명령을 다시 만들 필요 없이 메뉴 막대에서 remote를 연결하고, 상태를 보고, Finder나 편집기에서 다시 열 수 있습니다.",
        },
        sections: [
          { type: "copy", title: "SSHFS GUI가 해결하는 것", paragraphs: ["CLI SSHFS는 일회성 작업에는 괜찮지만, 여러 호스트와 고정 mount point, 절전 이후 확인 작업이 필요해지면 GUI의 이점이 커집니다."], bullets: ["터미널 출력을 읽지 않아도 상태가 보입니다.", "저장된 remote로 반복 입력과 실수를 줄입니다.", "자격 증명을 Keychain에 둘 수 있습니다.", "mount 이후 Finder와 편집기가 로컬처럼 동작합니다."] },
          { type: "cards", title: "CLI-only SSHFS 와 GUI-first SSHFS", intro: "셸은 유연하지만 GUI-first는 반복적인 운영 작업을 크게 줄여 줍니다.", cards: [{ title: "CLI-only SSHFS", body: "스크립트화에는 좋지만 retries, 상태 확인, mount point 정리, 오류 판독을 직접 맡아야 합니다." }, { title: "GUI-first SSHFS", body: "저장된 remote, 명확한 상태, recovery, 진단이 필요할 때 더 잘 맞습니다." }], columns: 2 },
          { type: "copy", title: "Finder 마운트와 SFTP 클라이언트의 차이", paragraphs: ["SFTP 클라이언트는 파일 전송에 적합하지만, SSHFS mount는 Finder 미리보기, 편집기 인덱싱, 일반 폴더 중심 작업에 더 잘 맞습니다."] },
          { type: "copy", title: "macFUSEGui의 위치", paragraphs: ["macFUSEGui는 macFUSE와 sshfs 위의 제어 계층으로, remote 수명주기, 자격 증명, system event 이후 recovery, 진단에 집중합니다."], actions: [{ kind: "page", pageId: "install", style: "primary", labelKey: "openInstallGuide" }, { kind: "page", pageId: "troubleshooting", style: "secondary", labelKey: "openTroubleshooting" }] },
        ],
      },
      install: {
        cardTitle: "Mac에서 macFUSE 및 SSHFS 설치",
        cardDescription: "필수 조건에서 첫 usable mount까지 macFUSEGui 도입을 빠르게 진행합니다.",
        title: "Mac에서 macFUSE 및 SSHFS 설치 | macFUSEGui 가이드",
        metaDescription:
          "Mac에서 macFUSE와 SSHFS를 설치하고, 올바른 macFUSEGui 빌드를 선택하고, 첫 실행 승인을 완료한 뒤 안정적인 첫 원격 마운트까지 빠르게 진행하세요.",
        hero: {
          eyebrow: "설치 가이드",
          lead:
            "이 페이지는 가장 짧은 경로에 초점을 둡니다. <strong>macFUSE</strong> 와 <strong>SSHFS</strong> 를 설치하고, 올바른 빌드를 선택하고, 첫 승인을 마친 뒤 첫 remote를 테스트합니다.",
        },
        sections: [
          { type: "copy", title: "1단계: 필수 구성요소 설치", paragraphs: ["먼저 macFUSE, 다음으로 sshfs를 설치합니다. macFUSEGui는 두 구성요소 모두에 의존합니다."], code: "brew install --cask macFUSE\nbrew install gromgit/fuse/sshfs-mac" },
          { type: "copy", title: "2단계: 올바른 빌드 선택", paragraphs: ["<code class=\"font-mono text-sm\">uname -m</code> 으로 아키텍처를 확인합니다. <code class=\"font-mono text-sm\">arm64</code> 는 Apple Silicon, <code class=\"font-mono text-sm\">x86_64</code> 는 Intel입니다.", "잘못된 빌드를 받는 것은 흔하지만 피할 수 있는 실수입니다."], code: "uname -m" },
          { type: "copy", title: "3단계: 첫 실행 승인 완료", paragraphs: ["서명되지 않은 빌드를 Finder에서 우클릭으로 한 번 엽니다.", "macOS가 계속 차단하면 개인정보 보호 및 보안에서 허용합니다."] },
          { type: "copy", title: "4단계: 첫 remote 추가", ordered: ["host, 사용자, 인증 방식, 원격 경로, 로컬 mount point를 입력합니다.", "UI에서 연결 테스트를 진행합니다.", "마운트된 경로를 Finder나 편집기에서 엽니다."] },
          { type: "copy", title: "5단계: 실패할 때", bullets: ["macFUSE와 sshfs를 다시 확인합니다.", "다운로드한 빌드가 맞는지 확인합니다.", "첫 승인 절차를 점검합니다.", "인증, recovery, mount point 문제는 troubleshooting으로 넘어갑니다."], actions: [{ kind: "page", pageId: "troubleshooting", style: "primary", labelKey: "openTroubleshooting" }, { kind: "page", pageId: "product", style: "secondary" }] },
        ],
      },
      troubleshooting: {
        cardTitle: "macFUSEGui 문제 해결",
        cardDescription: "설치, 인증, mount point, recovery 문제를 단계적으로 분리합니다.",
        title: "macFUSEGui 문제 해결 | Mac의 SSHFS 마운트 문제 수정",
        metaDescription:
          "macOS에서 macFUSEGui 문제를 해결하세요. 첫 실행 승인, 인증 오류, 오래된 SSHFS 마운트, 마운트 포인트 충돌, 재연결 실패를 다룹니다.",
        hero: {
          eyebrow: "지원 가이드",
          lead:
            "mount가 연결되지 않거나, 절전 후 stale 상태가 되거나, macOS가 앱을 차단하는 경우 이 페이지를 통해 원인을 필수 조건, 인증, mount 상태, recovery 중 어디에 있는지 좁힐 수 있습니다.",
        },
        sections: [
          { type: "copy", title: "1. 필수 조건 문제", paragraphs: ["아무것도 마운트되지 않는다면 먼저 macFUSE와 sshfs가 설치되었는지 확인하세요."], code: "brew install --cask macFUSE\nbrew install gromgit/fuse/sshfs-mac" },
          { type: "copy", title: "2. 첫 실행 승인 문제", paragraphs: ["서명되지 않은 빌드는 한 번의 승인이 필요합니다. Finder에서 우클릭으로 앱을 여세요.", "그 후 개인정보 보호 및 보안에 승인 안내가 있는지 확인합니다."] },
          { type: "copy", title: "3. 인증 및 호스트 정보 문제", bullets: ["hostname, 사용자명, 원격 경로를 다시 확인합니다.", "앱 안에서 자격 증명을 다시 테스트합니다.", "붙여 넣은 비밀번호가 의심되면 깔끔하게 다시 저장합니다."] },
          { type: "copy", title: "4. mount point 충돌", paragraphs: ["SSH 연결이 살아 있어도 로컬 경로가 이미 사용 중이거나 stale mount를 가리키면 실패할 수 있습니다. 각 remote마다 고유한 로컬 경로를 사용하세요."] },
          { type: "copy", title: "5. 절전, 깨우기, 네트워크 복구 문제", paragraphs: ["macFUSEGui는 원하는 remote를 절전, 깨우기, 네트워크 복귀 후 복원하려고 합니다. stale 상태가 계속되면 먼저 끊고 경로가 실제로 살아났는지 확인한 뒤 다시 연결하세요.", "반복되면 진단을 복사해 recovery 어느 단계에서 실패하는지 확인하세요."] },
          { type: "copy", title: "6. stale 또는 깨진 mount", paragraphs: ["Finder에는 remote가 보이지만 경로가 응답하지 않는다면 stale mount로 취급하세요. 먼저 앱에서 끊으세요."] },
          { type: "copy", title: "7. 추측보다 진단 먼저", paragraphs: ["진단 스냅샷은 추측을 줄이기 위해 있습니다. 환경, 상태, 최근 이벤트를 복사한 뒤 문제를 올리세요."], actions: [{ kind: "page", pageId: "product", style: "primary", labelKey: "backToProductGuide" }, { kind: "page", pageId: "sshfs", style: "secondary", labelKey: "compareWorkflows" }] },
        ],
      },
    },
  },
};

export const siteContent = Object.fromEntries(
  localeDefinitions.map((locale) => {
    const overrides =
      locale.slug === "en"
        ? {}
        : deepMerge(localeUiOverrides[locale.slug] ?? {}, localePageOverrides[locale.slug] ?? {});
    return [locale.slug, deepMerge(englishContent, overrides)];
  }),
);
