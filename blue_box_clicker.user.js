// ==UserScript==
// @name         Fully Automated Blue Box Clicker
// @namespace    http://tampermonkey.net/
// @version      11.0
// @description  Automatically plays, auto-clicks the blue box, downloads silently, and moves to the next page.
// @author       Your Name
// @match        *://*/*
// @grant        GM_download
// @run-at       document-end
// ==/UserScript==

(function() {
    'use strict';

    const MARKER = 'has-download-box';
    const BOX_ATTR = 'data-bluebox';

    // Remove all old blue boxes and unmark all videos so they can be re-processed
    function cleanupOldBoxes() {
        document.querySelectorAll('[' + BOX_ATTR + ']').forEach(box => box.remove());
        document.querySelectorAll('.' + MARKER).forEach(v => v.classList.remove(MARKER));
    }

    function clickNextOrLoadMore() {
        const elements = document.querySelectorAll('button, a, span, div');
        let targetButton = null;

        for (let el of elements) {
            const text = el.textContent.trim().toLowerCase();

            if (text === 'next' || text.includes('next →') || text.includes('next >')) {
                targetButton = el;
                break;
            } else if (text === 'load more' || text === 'loadmore' || text.includes('load more')) {
                targetButton = el;
            }
        }

        if (targetButton) {
            console.log('[BlueBox] Clicking Next / Load More...');
            targetButton.click();

            // After navigation, clean up and re-scan for new videos
            // Stagger re-scans to catch content that loads at different speeds
            setTimeout(() => { cleanupOldBoxes(); scanForVideos(); }, 1000);
            setTimeout(() => { cleanupOldBoxes(); scanForVideos(); }, 2000);
            setTimeout(() => { cleanupOldBoxes(); scanForVideos(); }, 3500);
        } else {
            console.log('[BlueBox] No Next or Load More button found.');
        }
    }

    function getVideoUrl(video) {
        let url = video.src;
        if (!url || url === '') {
            const sourceTag = video.querySelector('source');
            if (sourceTag) url = sourceTag.src;
        }
        if (!url || url === '') {
            url = video.currentSrc;
        }
        return url || null;
    }

    function triggerDownload(video, blueBox) {
        const videoUrl = getVideoUrl(video);
        if (!videoUrl) {
            console.log('[BlueBox] No video URL found, retrying in 200ms...');
            setTimeout(() => triggerDownload(video, blueBox), 200);
            return;
        }

        let originalName = videoUrl.split('/').pop().split('?')[0];
        if (!originalName || !originalName.includes('.')) {
            originalName = 'video.mp4';
        }

        console.log('[BlueBox] Downloading:', originalName);
        blueBox.style.backgroundColor = 'rgb(0, 0, 150)';

        GM_download({
            url: videoUrl,
            name: originalName,
            onload: () => {
                console.log('[BlueBox] Download confirmed. Moving to next...');
                blueBox.style.backgroundColor = 'rgb(0, 255, 0)';
                setTimeout(clickNextOrLoadMore, 500);
            },
            onerror: (err) => {
                console.error('[BlueBox] Download failed:', err);
                blueBox.style.backgroundColor = 'rgb(255, 0, 0)';
                setTimeout(clickNextOrLoadMore, 500);
            }
        });
    }

    function setupVideoControls(video) {
        if (video.classList.contains(MARKER)) return;
        video.classList.add(MARKER);

        const blueBox = document.createElement('div');
        blueBox.setAttribute(BOX_ATTR, 'true');
        blueBox.style.width = '40px';
        blueBox.style.height = '40px';
        blueBox.style.backgroundColor = 'rgb(0, 0, 255)';
        blueBox.style.position = 'absolute';
        blueBox.style.zIndex = '2147483647';
        blueBox.style.cursor = 'pointer';
        blueBox.style.borderRadius = '0px';

        function positionBox() {
            const rect = video.getBoundingClientRect();
            if (rect.width === 0 || rect.height === 0) {
                blueBox.style.display = 'none';
                return;
            }
            blueBox.style.display = 'block';
            blueBox.style.top = (rect.top + window.scrollY) + 'px';
            blueBox.style.left = (rect.left + window.scrollX + rect.width - 40) + 'px';
        }

        positionBox();
        window.addEventListener('resize', positionBox);
        window.addEventListener('scroll', positionBox);

        blueBox.addEventListener('click', (e) => {
            if (e) e.stopPropagation();
            triggerDownload(video, blueBox);
        });

        document.body.appendChild(blueBox);

        // AUTOMATION: fire instantly if URL is ready, otherwise play and poll
        const immediateUrl = getVideoUrl(video);
        if (immediateUrl) {
            console.log('[BlueBox] URL available immediately, firing download...');
            triggerDownload(video, blueBox);
        } else {
            video.muted = true;
            video.play().then(() => {
                let attempts = 0;
                const pollInterval = setInterval(() => {
                    attempts++;
                    const url = getVideoUrl(video);
                    if (url) {
                        clearInterval(pollInterval);
                        console.log('[BlueBox] URL resolved after play, firing download...');
                        triggerDownload(video, blueBox);
                    } else if (attempts >= 30) {
                        clearInterval(pollInterval);
                        console.log('[BlueBox] Gave up waiting for video URL.');
                    }
                }, 100);
            }).catch(() => {
                video.addEventListener('play', () => {
                    const pollInterval = setInterval(() => {
                        const url = getVideoUrl(video);
                        if (url) {
                            clearInterval(pollInterval);
                            triggerDownload(video, blueBox);
                        }
                    }, 100);
                    setTimeout(() => clearInterval(pollInterval), 3000);
                }, { once: true });
            });
        }
    }

    // Scan the page for any unprocessed videos and observe them
    function scanForVideos() {
        document.querySelectorAll('video').forEach(v => {
            if (!v.classList.contains(MARKER)) {
                visibilityObserver.observe(v);
            }
        });
    }

    const visibilityObserver = new IntersectionObserver((entries) => {
        entries.forEach(entry => {
            if (entry.isIntersecting) {
                const video = entry.target;
                if (video.offsetWidth > 0 && video.offsetHeight > 0) {
                    setupVideoControls(video);
                    visibilityObserver.unobserve(video);
                }
            }
        });
    }, { root: null, threshold: 0.1 });

    // Initial scan
    scanForVideos();

    // Watch for dynamically added videos
    const observer = new MutationObserver((mutations) => {
        for (let mutation of mutations) {
            for (let node of mutation.addedNodes) {
                if (node.nodeName === 'VIDEO') {
                    if (!node.classList.contains(MARKER)) visibilityObserver.observe(node);
                } else if (node.querySelectorAll) {
                    node.querySelectorAll('video').forEach(v => {
                        if (!v.classList.contains(MARKER)) visibilityObserver.observe(v);
                    });
                }
            }
        }
    });
    observer.observe(document.body, { childList: true, subtree: true });

    // FALLBACK: Also watch for URL changes (SPA navigation via pushState/popstate)
    let lastUrl = location.href;
    const urlWatcher = setInterval(() => {
        if (location.href !== lastUrl) {
            lastUrl = location.href;
            console.log('[BlueBox] URL changed, re-scanning...');
            setTimeout(() => { cleanupOldBoxes(); scanForVideos(); }, 1000);
            setTimeout(() => { cleanupOldBoxes(); scanForVideos(); }, 2500);
        }
    }, 500);
})();
