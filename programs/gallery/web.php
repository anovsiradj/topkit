<!DOCTYPE html>
<html lang="en" data-bs-theme="light">

<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>SPA Media Gallery</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.2/dist/css/bootstrap.min.css" rel="stylesheet">
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.11.0/font/bootstrap-icons.css">
    <style>
        body {
            height: 100vh;
            overflow: hidden;
        }

        .row {
            flex-wrap: nowrap;
        }

        .sidebar {
            height: 100vh;
            overflow-y: auto;
            position: relative;
            min-width: 200px;
            max-width: 60%;
            user-select: none;
        }

        .main-content {
            height: 100vh;
            overflow-y: auto;
            position: relative;
            flex: 1 0 0;
        }

        .resize-handle {
            position: absolute;
            right: 0;
            top: 0;
            bottom: 0;
            width: 6px;
            cursor: col-resize;
            background: transparent;
            transition: background 0.2s;
            z-index: 1000;
            display: flex;
            align-items: center;
            justify-content: center;
        }

        .resize-handle::after {
            content: '';
            width: 2px;
            height: 40px;
            background: rgba(var(--bs-secondary-rgb), 0.3);
            border-radius: 2px;
            transition: background 0.2s;
        }

        .resize-handle:hover::after,
        .resize-handle.active::after {
            background: var(--bs-primary);
            width: 3px;
        }

        .resize-handle:hover,
        .resize-handle.active {
            background: rgba(var(--bs-primary-rgb), 0.1);
        }

        .sidebar.resizing {
            pointer-events: none;
        }

        .file-item {
            cursor: pointer;
            transition: all 0.2s;
            border-left: 3px solid transparent;
            outline: none;
            position: relative;
        }

        .file-item:hover,
        .file-item:focus-visible {
            background: rgba(var(--bs-secondary-rgb), 0.15);
            border-left-color: var(--bs-secondary);
        }

        .file-item:focus-visible {
            box-shadow: inset 0 0 0 2px rgba(var(--bs-primary-rgb), 0.5);
            z-index: 10;
        }

        .file-item.active {
            background: var(--bs-primary) !important;
            color: white;
            border-left-color: var(--bs-primary-border-subtle);
        }

        .file-item.active:focus-visible {
            box-shadow: inset 0 0 0 2px rgba(255, 255, 255, 0.5);
        }

        .kbd-shortcut {
            position: fixed;
            bottom: 20px;
            right: 20px;
            background: rgba(33, 37, 41, 0.9);
            color: white;
            padding: 1rem;
            border-radius: 0.5rem;
            font-size: 0.875rem;
            z-index: 9999;
            backdrop-filter: blur(10px);
            border: 1px solid rgba(255, 255, 255, 0.1);
            max-width: 300px;
            opacity: 0;
            transform: translateY(20px);
            transition: all 0.3s;
            pointer-events: none;
        }

        .kbd-shortcut.visible {
            opacity: 1;
            transform: translateY(0);
        }

        .kbd-shortcut kbd {
            background: rgba(255, 255, 255, 0.2);
            padding: 0.2rem 0.4rem;
            border-radius: 0.25rem;
            font-family: monospace;
            font-size: 0.9em;
        }

        .kbd-shortcut .shortcut-row {
            display: flex;
            justify-content: space-between;
            margin-bottom: 0.5rem;
        }

        .kbd-shortcut .shortcut-row:last-child {
            margin-bottom: 0;
        }

        .media-container {
            flex: 1;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 2rem;
            background: #1a1d20;
            border: 1px solid var(--bs-border-color);
            border-radius: 0.5rem;
            margin: 1rem;
            min-height: 60vh;
            position: relative;
            overflow: hidden;
            cursor: grab;
            outline: none;
        }

        .media-container:active {
            cursor: grabbing;
        }

        .media-container.video-mode {
            cursor: default;
        }

        .media-container:focus-visible {
            box-shadow: 0 0 0 3px rgba(var(--bs-primary-rgb), 0.5);
        }

        .media-wrapper {
            transition: transform 0.1s ease-out;
            transform-origin: center center;
            max-width: 100%;
            max-height: 70vh;
            box-shadow: 0 10px 40px rgba(0, 0, 0, 0.5);
            border-radius: 0.5rem;
            background: #000;
        }

        .media-wrapper img {
            max-width: 100%;
            max-height: 70vh;
            display: block;
            border-radius: 0.5rem;
            user-select: none;
            -webkit-user-drag: none;
        }

        .media-wrapper video {
            max-width: 100%;
            max-height: 70vh;
            border-radius: 0.5rem;
            display: block;
            background: #000;
        }

        /* Video loading state */
        .video-loading {
            position: absolute;
            top: 50%;
            left: 50%;
            transform: translate(-50%, -50%);
            color: white;
            font-size: 2rem;
            pointer-events: none;
            opacity: 0;
            transition: opacity 0.3s;
        }

        .media-container.video-mode.loading .video-loading {
            opacity: 1;
        }

        .search-box {
            position: sticky;
            top: 0;
            z-index: 100;
        }

        .empty-state {
            text-align: center;
            color: var(--bs-secondary);
            margin-top: 20vh;
        }

        .zoom-controls {
            position: absolute;
            bottom: 20px;
            left: 50%;
            transform: translateX(-50%);
            background: rgba(33, 37, 41, 0.9);
            backdrop-filter: blur(10px);
            padding: 0.5rem;
            border-radius: 2rem;
            display: flex;
            align-items: center;
            gap: 0.5rem;
            box-shadow: 0 4px 20px rgba(0, 0, 0, 0.4);
            border: 1px solid rgba(255, 255, 255, 0.1);
            z-index: 100;
            opacity: 0;
            transition: opacity 0.3s;
        }

        .media-container:hover .zoom-controls,
        .zoom-controls.visible,
        .media-container:focus-within .zoom-controls {
            opacity: 1;
        }

        .zoom-controls .btn {
            border-radius: 50%;
            width: 36px;
            height: 36px;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 0;
            border: none;
            background: rgba(255, 255, 255, 0.1);
            color: white;
        }

        .zoom-controls .btn:hover,
        .zoom-controls .btn:focus-visible {
            background: rgba(255, 255, 255, 0.3);
            outline: 2px solid white;
        }

        .zoom-level {
            color: white;
            font-size: 0.875rem;
            min-width: 60px;
            text-align: center;
            font-variant-numeric: tabular-nums;
        }

        .video-mode .zoom-controls {
            display: none !important;
        }

        body.resizing {
            cursor: col-resize !important;
            user-select: none;
        }

        body.resizing * {
            cursor: col-resize !important;
        }

        #themeToggle {
            transition: transform 0.3s;
        }

        #themeToggle:hover {
            transform: rotate(15deg);
        }

        .playback-indicator {
            position: absolute;
            top: 20px;
            right: 20px;
            background: rgba(0, 0, 0, 0.7);
            color: white;
            padding: 0.5rem 1rem;
            border-radius: 2rem;
            font-size: 0.875rem;
            pointer-events: none;
            opacity: 0;
            transition: opacity 0.3s;
        }

        .media-container.video-mode:hover .playback-indicator,
        .playback-indicator.visible {
            opacity: 1;
        }
    </style>
</head>

<body class="bg-body">

    <div class="container-fluid">
        <div class="row" id="mainRow">
            <div class="col-md-3 col-lg-3 sidebar p-0 bg-body border-end" id="sidebar" tabindex="-1" role="listbox" aria-label="File list">
                <div class="search-box p-3 border-bottom bg-body">
                    <div class="input-group mb-3">
                        <span class="input-group-text bg-body">🔍</span>
                        <input type="search" class="form-control bg-body" id="searchInput" placeholder="Filter files... (Press '/' to focus)" aria-label="Search files">
                    </div>
                    <div class="d-flex justify-content-between align-items-center">
                        <small class="text-muted" id="fileCount">Loading...</small>
                        <button class="btn btn-sm btn-outline-secondary border-0" id="themeToggle" title="Toggle dark mode (Press T)">
                            🌙
                        </button>
                    </div>
                </div>
                <div class="list-group list-group-flush" id="fileList" role="presentation"></div>
                <div class="resize-handle" id="resizeHandle" title="Drag to resize"></div>
            </div>

            <div class="col-md-9 col-lg-9 main-content bg-body" id="mainContent">
                <div id="viewer" class="h-100 d-flex flex-column">
                    <div id="emptyState" class="empty-state">
                        <div class="display-1 mb-3 opacity-50">🖼️</div>
                        <h3 class="h4">Select a file to view</h3>
                        <p class="text-muted">Use ↑↓ to navigate, Enter to open, ? for help</p>
                    </div>

                    <div id="mediaWrapper" class="d-none flex-column h-100">
                        <div class="p-3 border-bottom bg-body-tertiary d-flex justify-content-between align-items-center shadow-sm">
                            <div class="overflow-hidden">
                                <h5 class="mb-0 text-truncate" id="displayFileName"></h5>
                                <small class="text-muted" id="displayFileType"></small>
                            </div>
                            <span class="badge bg-primary" id="typeBadge"></span>
                        </div>
                        <div class="media-container video-mode" id="mediaContainer" tabindex="0"
                            aria-label="Media viewer. Use +/- to zoom on images, arrows to pan when zoomed, SPACE to play/pause video, ESC to close.">
                            <div class="playback-indicator" id="playbackIndicator">
                                <i class="bi bi-play-fill"></i> Auto-playing
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </div>

    <div class="kbd-shortcut" id="kbdHelp" role="dialog" aria-label="Keyboard shortcuts">
        <div class="shortcut-row"><span><kbd>↑</kbd> <kbd>↓</kbd></span> <span>Navigate files</span></div>
        <div class="shortcut-row"><span><kbd>Enter</kbd></span> <span>Open file</span></div>
        <div class="shortcut-row"><span><kbd>ESC</kbd></span> <span>Close view</span></div>
        <div class="shortcut-row"><span><kbd>Space</kbd></span> <span>Play/Pause video</span></div>
        <div class="shortcut-row"><span><kbd>+</kbd> <kbd>-</kbd></span> <span>Zoom in/out</span></div>
        <div class="shortcut-row"><span><kbd>0</kbd></span> <span>Reset zoom</span></div>
        <div class="shortcut-row"><span><kbd>←</kbd> <kbd>→</kbd></span> <span>Pan when zoomed</span></div>
        <div class="shortcut-row"><span><kbd>/</kbd></span> <span>Focus search</span></div>
        <div class="shortcut-row"><span><kbd>T</kbd></span> <span>Toggle theme</span></div>
        <div class="shortcut-row"><span><kbd>?</kbd></span> <span>Toggle this help</span></div>
    </div>

    <!-- TEMPLATES -->
    <template id="listItemTpl">
        <div class="list-group-item file-item d-flex justify-content-between align-items-center py-3 bg-body border-0 border-bottom"
            role="option"
            tabindex="-1"
            aria-selected="false">
            <div class="d-flex align-items-center overflow-hidden">
                <span class="me-3 fs-5 file-icon" aria-hidden="true"></span>
                <div class="text-truncate">
                    <div class="fw-medium file-name"></div>
                    <small class="text-muted file-meta"></small>
                </div>
            </div>
            <span class="badge rounded-pill file-badge"></span>
        </div>
    </template>

    <template id="imageTpl">
        <div class="media-wrapper" id="zoomTarget">
            <img src="" alt="" draggable="false">
        </div>
        <div class="zoom-controls" role="toolbar" aria-label="Zoom controls">
            <button class="btn btn-sm" data-zoom="out" title="Zoom Out (-)" aria-label="Zoom out">
                <i class="bi bi-zoom-out" aria-hidden="true"></i>
            </button>
            <span class="zoom-level" aria-live="polite" aria-atomic="true">100%</span>
            <button class="btn btn-sm" data-zoom="in" title="Zoom In (+)" aria-label="Zoom in">
                <i class="bi bi-zoom-in" aria-hidden="true"></i>
            </button>
            <button class="btn btn-sm" data-zoom="reset" title="Reset Zoom (0)" aria-label="Reset zoom">
                <i class="bi bi-fullscreen" aria-hidden="true"></i>
            </button>
            <button class="btn btn-sm" data-zoom="fit" title="Fit to Screen" aria-label="Fit to screen">
                <i class="bi bi-arrows-fullscreen" aria-hidden="true"></i>
            </button>
        </div>
    </template>

    <template id="videoTpl">
        <div class="media-wrapper">
            <video class="w-100" autoplay muted playsinline loop controls aria-label="Video content">
                <source src="" type="video/mp4">
                Your browser does not support the video tag.
            </video>
        </div>
        <div class="video-loading">
            <div class="spinner-border text-light" role="status">
                <span class="visually-hidden">Loading video...</span>
            </div>
        </div>
    </template>

    <template id="noResultsTpl">
        <div class="p-4 text-center text-muted bg-body" role="status">
            <div class="fs-1 mb-2">🔍</div>
            <div>No files match your search</div>
        </div>
    </template>

    <script src="https://code.jquery.com/jquery-3.7.1.min.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.2/dist/js/bootstrap.bundle.min.js"></script>

    <script>
        // Mock Data
        let mediaFiles = [];

        // State Management
        let filteredFiles = [...mediaFiles];
        let currentSelection = null;
        let focusedIndex = -1;
        let currentZoom = 1;
        let isDragging = false;
        let startX, startY, translateX = 0,
            translateY = 0;
        let isResizing = false;
        let helpVisible = false;
        let currentVideo = null; // Track current video for play/pause control

        const MIN_ZOOM = 0.5;
        const MAX_ZOOM = 4;
        const ZOOM_STEP = 0.25;
        const PAN_STEP = 50;
        const MIN_SIDEBAR_WIDTH = 200;
        const MAX_SIDEBAR_WIDTH = $(window).width() * 0.6;

        // jQuery Cache
        const $sidebar = $('#sidebar');
        const $mainContent = $('#mainContent');
        const $resizeHandle = $('#resizeHandle');
        const $html = $('html');
        const $body = $('body');
        const $searchInput = $('#searchInput');
        const $mediaContainer = $('#mediaContainer');
        const $fileList = $('#fileList');
        const $playbackIndicator = $('#playbackIndicator');

        // Initialize
        const savedWidth = localStorage.getItem('gallery-sidebar-width');
        if (savedWidth) applySidebarWidth(parseInt(savedWidth));

        const savedTheme = localStorage.getItem('gallery-theme') || 'light';
        $html.attr('data-bs-theme', savedTheme);
        $('#themeToggle').html(savedTheme === 'light' ? '🌙' : '☀️');

        $(async function() {
            mediaFiles = await $.get('?list');
            filteredFiles = [...mediaFiles]

            renderFileList(filteredFiles);
            updateFileCount(filteredFiles.length);
            $sidebar.attr('tabindex', '0').focus();

            $searchInput.on('input', function() {
                const query = $(this).val().toLowerCase().trim();
                filteredFiles = query ? mediaFiles.filter(f => f.name.toLowerCase().includes(query)) : [...mediaFiles];
                renderFileList(filteredFiles);
                updateFileCount(filteredFiles.length);
                focusedIndex = -1;
            });

            // Resize functionality
            $resizeHandle.on('mousedown touchstart', function(e) {
                isResizing = true;
                $resizeHandle.addClass('active');
                $sidebar.addClass('resizing');
                $body.addClass('resizing');
                if (e.type === 'touchstart') e.preventDefault();
            });

            $(document).on('mousemove touchmove', function(e) {
                if (!isResizing) return;
                let clientX = e.type === 'touchmove' ? e.originalEvent.touches[0].clientX : e.clientX;
                let newWidth = Math.max(MIN_SIDEBAR_WIDTH, Math.min(clientX, MAX_SIDEBAR_WIDTH));
                applySidebarWidth(newWidth);
            });

            $(document).on('mouseup touchend', function() {
                if (isResizing) {
                    isResizing = false;
                    $resizeHandle.removeClass('active');
                    $sidebar.removeClass('resizing');
                    $body.removeClass('resizing');
                    localStorage.setItem('gallery-sidebar-width', $sidebar.outerWidth());
                }
            });

            $('#themeToggle').on('click', toggleTheme);

            // Zoom wheel
            $mediaContainer.on('wheel', function(e) {
                if ($(this).hasClass('video-mode')) return;
                e.preventDefault();
                const delta = e.originalEvent.deltaY > 0 ? -ZOOM_STEP : ZOOM_STEP;
                applyZoom(currentZoom + delta);
            });

            // Zoom buttons
            $mediaContainer.on('click', '[data-zoom]', function(e) {
                e.stopPropagation();
                const action = $(this).data('zoom');
                handleZoomAction(action);
            });

            // Pan mouse
            $mediaContainer.on('mousedown', function(e) {
                if ($(this).hasClass('video-mode') || currentZoom <= 1) return;
                isDragging = true;
                startX = e.clientX - translateX;
                startY = e.clientY - translateY;
                $(this).css('cursor', 'grabbing');
            });

            $(document).on('mousemove', function(e) {
                if (!isDragging) return;
                e.preventDefault();
                translateX = e.clientX - startX;
                translateY = e.clientY - startY;
                updateTransform();
            });

            $(document).on('mouseup', function() {
                if (isDragging) {
                    isDragging = false;
                    if (!$mediaContainer.hasClass('video-mode')) {
                        $mediaContainer.css('cursor', currentZoom > 1 ? 'grab' : 'default');
                    }
                }
            });

            // Global Keyboard Navigation
            $(document).on('keydown', handleKeyboard);
            $fileList.on('focusin', '.file-item', function() {
                focusedIndex = $(this).index();
            });
        });

        function handleKeyboard(e) {
            if (document.activeElement === $searchInput[0]) {
                if (e.key === 'Escape') {
                    $searchInput.blur();
                    $sidebar.focus();
                    e.preventDefault();
                }
                return;
            }

            const $items = $fileList.find('.file-item');
            const hasItems = $items.length > 0;
            const isViewerOpen = !$('#mediaWrapper').hasClass('d-none');
            const isImageView = isViewerOpen && !$mediaContainer.hasClass('video-mode');
            const isVideoView = isViewerOpen && $mediaContainer.hasClass('video-mode');

            switch (e.key) {
                case 'ArrowDown':
                case 'j':
                case 'J':
                    e.preventDefault();
                    if (hasItems) {
                        focusedIndex = Math.min(focusedIndex + 1, $items.length - 1);
                        focusItem($items.eq(focusedIndex));
                    }
                    break;

                case 'ArrowUp':
                case 'k':
                case 'K':
                    e.preventDefault();
                    if (hasItems) {
                        focusedIndex = Math.max(focusedIndex - 1, 0);
                        focusItem($items.eq(focusedIndex));
                    }
                    break;

                case 'Enter':
                case ' ':
                    if (isVideoView && e.key === ' ') {
                        e.preventDefault();
                        toggleVideoPlayback();
                    } else if (focusedIndex >= 0 && hasItems) {
                        e.preventDefault();
                        $items.eq(focusedIndex).trigger('click');
                    }
                    break;

                case 'Home':
                    e.preventDefault();
                    if (hasItems) {
                        focusedIndex = 0;
                        focusItem($items.first());
                    }
                    break;

                case 'End':
                    e.preventDefault();
                    if (hasItems) {
                        focusedIndex = $items.length - 1;
                        focusItem($items.last());
                    }
                    break;

                case 'Escape':
                    if (isViewerOpen) {
                        e.preventDefault();
                        closeViewer();
                    } else if (helpVisible) {
                        toggleHelp();
                    }
                    break;

                case '+':
                case '=':
                    if (isImageView) {
                        e.preventDefault();
                        applyZoom(currentZoom + ZOOM_STEP);
                    }
                    break;

                case '-':
                case '_':
                    if (isImageView) {
                        e.preventDefault();
                        applyZoom(currentZoom - ZOOM_STEP);
                    }
                    break;

                case '0':
                    if (isImageView) {
                        e.preventDefault();
                        resetZoom();
                    }
                    break;

                case 'ArrowLeft':
                    if (isImageView && currentZoom > 1) {
                        e.preventDefault();
                        translateX += PAN_STEP;
                        updateTransform();
                    } else if (isVideoView && currentVideo) {
                        e.preventDefault();
                        currentVideo.currentTime -= 5; // Skip back 5s
                    }
                    break;

                case 'ArrowRight':
                    if (isImageView && currentZoom > 1) {
                        e.preventDefault();
                        translateX -= PAN_STEP;
                        updateTransform();
                    } else if (isVideoView && currentVideo) {
                        e.preventDefault();
                        currentVideo.currentTime += 5; // Skip forward 5s
                    }
                    break;

                case '/':
                    e.preventDefault();
                    $searchInput.focus().select();
                    break;

                case 't':
                case 'T':
                    e.preventDefault();
                    toggleTheme();
                    break;

                case '?':
                    e.preventDefault();
                    toggleHelp();
                    break;
            }
        }

        function focusItem($item) {
            $item.attr('tabindex', '0').focus();
            $item.siblings().attr('tabindex', '-1');

            const itemTop = $item.position().top;
            const itemBottom = itemTop + $item.outerHeight();
            const sidebarHeight = $sidebar.height();
            const scrollTop = $sidebar.scrollTop();

            if (itemTop < 0) {
                $sidebar.scrollTop(scrollTop + itemTop - 10);
            } else if (itemBottom > sidebarHeight) {
                $sidebar.scrollTop(scrollTop + (itemBottom - sidebarHeight) + 10);
            }
        }

        function toggleVideoPlayback() {
            if (!currentVideo) return;
            if (currentVideo.paused) {
                currentVideo.play();
                $playbackIndicator.html('<i class="bi bi-play-fill"></i> Playing').addClass('visible');
            } else {
                currentVideo.pause();
                $playbackIndicator.html('<i class="bi bi-pause-fill"></i> Paused').addClass('visible');
            }
            setTimeout(() => $playbackIndicator.removeClass('visible'), 2000);
        }

        function handleZoomAction(action) {
            switch (action) {
                case 'in':
                    applyZoom(currentZoom + ZOOM_STEP);
                    break;
                case 'out':
                    applyZoom(currentZoom - ZOOM_STEP);
                    break;
                case 'reset':
                    resetZoom();
                    break;
                case 'fit':
                    fitToScreen();
                    break;
            }
        }

        function toggleTheme() {
            const currentTheme = $html.attr('data-bs-theme');
            const newTheme = currentTheme === 'light' ? 'dark' : 'light';
            $html.attr('data-bs-theme', newTheme);
            localStorage.setItem('gallery-theme', newTheme);
            $('#themeToggle').html(newTheme === 'light' ? '🌙' : '☀️');
        }

        function toggleHelp() {
            helpVisible = !helpVisible;
            $('#kbdHelp').toggleClass('visible', helpVisible);
        }

        function closeViewer() {
            // Pause current video before closing
            if (currentVideo) {
                currentVideo.pause();
                currentVideo = null;
            }

            $('#mediaWrapper').addClass('d-none');
            $('#emptyState').removeClass('d-none');
            currentSelection = null;
            resetZoom();
            renderFileList(filteredFiles);
            $sidebar.focus();
        }

        function applySidebarWidth(width) {
            $sidebar.removeClass('col-md-3 col-lg-3').css({
                'flex': `0 0 ${width}px`,
                'max-width': '60%'
            });
            $mainContent.removeClass('col-md-9 col-lg-9').css('flex', '1 0 0');
        }

        function renderFileList(files) {
            $fileList.empty();

            if (files.length === 0) {
                $fileList.append($('#noResultsTpl').prop('content').cloneNode(true));
                focusedIndex = -1;
                return;
            }

            const $tpl = $('#listItemTpl');

            files.forEach((file, index) => {
                const $clone = $($tpl.prop('content').cloneNode(true));
                const $item = $clone.find('.file-item');

                $item.attr({
                    'data-id': file.id,
                    'data-index': index,
                    'aria-label': `${file.name}, ${file.type}, ${file.size}`
                });

                if (currentSelection === file.id) {
                    $item.addClass('active').attr('aria-selected', 'true');
                    $item.find('.file-meta').removeClass('text-muted').addClass('text-white-50');
                    focusedIndex = index;
                }

                const icon = file.type === 'video' ? '🎬' : '🖼️';
                $item.find('.file-icon').text(icon);
                $item.find('.file-name').text(file.name);
                $item.find('.file-meta').text(file.size);

                const badgeColor = file.type === 'video' ? 'bg-danger' : 'bg-success';
                $item.find('.file-badge').addClass(badgeColor).text(file.type);

                $item.on('click', () => loadFile(file));

                $fileList.append($clone);
            });
        }

        function loadFile(file) {
            // Stop previous video if exists
            if (currentVideo) {
                currentVideo.pause();
                currentVideo = null;
            }

            currentSelection = file.id;
            resetZoom();

            const $items = $fileList.find('.file-item');
            $items.removeClass('active').attr({
                'aria-selected': 'false',
                'tabindex': '-1'
            });
            $items.find('.file-meta').addClass('text-muted').removeClass('text-white-50');

            const $activeItem = $items.filter(`[data-id="${file.id}"]`);
            $activeItem.addClass('active').attr({
                'aria-selected': 'true',
                'tabindex': '0'
            }).focus();
            $activeItem.find('.file-meta').removeClass('text-muted').addClass('text-white-50');

            focusedIndex = $activeItem.index();

            $('#emptyState').addClass('d-none');
            $('#mediaWrapper').removeClass('d-none').css('display', 'flex');

            $('#displayFileName').text(file.name);
            $('#displayFileType').text(file.size);
            $('#typeBadge')
                .text(file.type.toUpperCase())
                .removeClass('bg-success bg-danger')
                .addClass(file.type === 'video' ? 'bg-danger' : 'bg-success');

            // Clear but keep the playback indicator
            $mediaContainer.empty().append($playbackIndicator);

            if (file.type === 'image') {
                const $clone = $($('#imageTpl').prop('content').cloneNode(true));
                $clone.find('img').attr({
                    'src': file.url,
                    'alt': file.name
                });
                $mediaContainer.removeClass('video-mode').append($clone);
                setTimeout(() => $mediaContainer.focus(), 100);
            } else if (file.type === 'video') {
                $mediaContainer.addClass('video-mode loading');
                const $clone = $($('#videoTpl').prop('content').cloneNode(true));
                const $video = $clone.find('video');

                // Store reference for keyboard controls
                currentVideo = $video[0];

                // Handle autoplay events
                $video.on('loadeddata', function() {
                    $mediaContainer.removeClass('loading');
                    $playbackIndicator.html('<i class="bi bi-play-fill"></i> Auto-playing').addClass('visible');
                    setTimeout(() => $playbackIndicator.removeClass('visible'), 3000);
                });

                $video.on('play', function() {
                    $playbackIndicator.html('<i class="bi bi-play-fill"></i> Playing').addClass('visible');
                    setTimeout(() => $playbackIndicator.removeClass('visible'), 1500);
                });

                $video.on('pause', function() {
                    if (!currentVideo.ended) {
                        $playbackIndicator.html('<i class="bi bi-pause-fill"></i> Paused').addClass('visible');
                    }
                });

                $video.on('ended', function() {
                    $playbackIndicator.html('<i class="bi bi-check-circle"></i> Ended').addClass('visible');
                });

                $video.on('volumechange', function() {
                    // Handle if user unmutes
                    if (!currentVideo.muted && currentVideo.volume > 0) {
                        $playbackIndicator.html('<i class="bi bi-volume-up"></i> Sound On').addClass('visible');
                        setTimeout(() => $playbackIndicator.removeClass('visible'), 2000);
                    }
                });

                $clone.find('source').attr('src', file.url);
                $mediaContainer.append($clone);
                $mediaContainer.focus();

                // Ensure autoplay starts (browsers may block it)
                currentVideo.play().catch(function(error) {
                    console.log("Autoplay prevented:", error);
                    $mediaContainer.removeClass('loading');
                    $playbackIndicator.html('<i class="bi bi-play-circle"></i> Click to play').addClass('visible');
                });
            }
        }

        function applyZoom(newZoom) {
            currentZoom = Math.max(MIN_ZOOM, Math.min(MAX_ZOOM, newZoom));
            updateTransform();
            updateZoomDisplay();

            if (currentZoom > 1) {
                $mediaContainer.css('cursor', 'grab');
            } else {
                $mediaContainer.css('cursor', 'default');
                translateX = 0;
                translateY = 0;
                updateTransform();
            }
        }

        function resetZoom() {
            currentZoom = 1;
            translateX = 0;
            translateY = 0;
            updateTransform();
            updateZoomDisplay();
            $mediaContainer.css('cursor', 'default');
        }

        function fitToScreen() {
            resetZoom();
        }

        function updateTransform() {
            $('#zoomTarget').css('transform', `translate(${translateX}px, ${translateY}px) scale(${currentZoom})`);
        }

        function updateZoomDisplay() {
            $('.zoom-level').text(Math.round(currentZoom * 100) + '%');
        }

        function updateFileCount(count) {
            $('#fileCount').text(`${count} file${count !== 1 ? 's' : ''}`);
        }

        $(window).on('resize', function() {
            const currentWidth = $sidebar.outerWidth();
            const maxWidth = $(window).width() * 0.6;
            if (currentWidth > maxWidth) applySidebarWidth(maxWidth);
        });
    </script>

</body>

</html>