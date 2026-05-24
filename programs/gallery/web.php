<!DOCTYPE html>
<html lang="en" data-bs-theme="dark">

<head>
	<meta charset="UTF-8">
	<meta name="viewport" content="width=device-width, initial-scale=1.0">
	<title>Local Server Gallery</title>

	<!-- Bootstrap v5.3 -->
	<link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.2/dist/css/bootstrap.min.css" rel="stylesheet">
	<!-- Bootstrap Icons v1 -->
	<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.11.3/font/bootstrap-icons.css">

	<link rel="stylesheet" href="web.css">
</head>

<body>
	<div class="gallery-container">
		<!-- Header -->
		<div class="gallery-header">
			<div class="d-flex justify-content-between align-items-center">
				<div>
					<h5 class="mb-0">Local Server Gallery</h5>
				</div>
				<div class="d-flex gap-2 align-items-center">
					<!-- Root Folder Selector -->
					<div class="input-group input-group-sm" style="width: auto; max-width: 250px;">
						<span class="input-group-text" id="root-folder-label">
							<i class="bi bi-folder"></i>
						</span>
						<input type="text" class="form-control" id="root-folder-input" 
							placeholder="Root folder path" value="<?php echo htmlspecialchars($root); ?>"
							aria-label="Root folder" aria-describedby="root-folder-label">
						<button class="btn btn-outline-secondary" type="button" id="change-root-btn" title="Change root folder">
							<i class="bi bi-arrow-clockwise"></i>
						</button>
					</div>
					
					<span class="text-muted me-2" id="file-count">Loading...</span>
					<select class="form-select form-select-sm" id="sort-select" style="width: auto; max-width: 150px;">
						<option value="name">Sort by Name</option>
						<option value="type">Sort by Type</option>
						<option value="size">Sort by Size</option>
						<option value="created_at">Sort by Created</option>
						<option value="modified_at">Sort by Modified</option>
					</select>
					<button class="btn btn-sm btn-outline-secondary" id="toggle-shortcuts" title="Keyboard Shortcuts">
						<i class="bi bi-question-circle"></i>
					</button>
				</div>
			</div>
		</div>

		<!-- Main Content -->
		<div class="gallery-content">
			<!-- Sidebar: Labels & Filters -->
			<div class="gallery-sidebar">
				<div class="sidebar-top">
					<div class="sidebar-section">
						<div class="search-box">
							<i class="bi bi-search"></i>
							<input type="text" id="search-input" placeholder="Search files..." autocomplete="off">
						</div>
					</div>
				</div>

				<div class="sidebar-section">
					<div class="sidebar-section-title">Filter by Type</div>
					<div class="filter-controls" id="type-filters">
						<button class="filter-btn active" data-filter="all">All</button>
						<button class="filter-btn" data-filter="image">Images</button>
						<button class="filter-btn" data-filter="video">Videos</button>
					</div>
				</div>

				<div class="sidebar-scroll">
					<div class="sidebar-section">
						<div class="sidebar-section-title">Filter By Labels</div>
						<div id="labels-container" class="tags-cloud"></div>
					</div>
				</div>
			</div>
			<!-- Main Viewer -->
			<div class="gallery-main">
				<!-- Gallery Grid View (Index/List) -->
				<div class="gallery-grid" id="gallery-grid"></div>

				<!-- Media Viewer (Hidden by default) -->
				<div class="gallery-viewer" id="viewer-container" style="display: none;">
					<div class="media-wrapper" id="media-wrapper">
						<div class="empty-state" id="empty-state">
							<i class="bi bi-images"></i>
							<p>No files loaded yet</p>
						</div>
					</div>

					<!-- Navigation Buttons -->
					<button class="viewer-nav-btn left" id="prev-btn" title="Previous (Arrow Left)">
						<i class="bi bi-chevron-left"></i>
					</button>
					<button class="viewer-nav-btn right" id="next-btn" title="Next (Arrow Right)">
						<i class="bi bi-chevron-right"></i>
					</button>

					<!-- Compact Toolbar -->
					<div class="viewer-toolbar compact" id="viewer-toolbar">
						<button class="toolbar-btn" id="play-btn" title="Play Slideshow (Space)">
							<i class="bi bi-play-fill"></i>
						</button>
						<button class="toolbar-btn" id="fullscreen-btn" title="Fullscreen (F)">
							<i class="bi bi-fullscreen"></i>
						</button>
						<button class="toolbar-btn" id="zoom-in-btn" title="Zoom In (+)">
							<i class="bi bi-zoom-in"></i>
						</button>
						<button class="toolbar-btn" id="zoom-out-btn" title="Zoom Out (-)">
							<i class="bi bi-zoom-out"></i>
						</button>
						<button class="toolbar-btn" id="rotate-btn" title="Rotate (R)">
							<i class="bi bi-arrow-clockwise"></i>
						</button>
						<div class="toolbar-divider"></div>
						<button class="toolbar-btn" id="info-btn" title="File Info (I)">
							<i class="bi bi-info-circle"></i>
						</button>
						<div class="toolbar-divider"></div>
						<button class="toolbar-btn" id="rename-btn" title="Rename (F2)">
							<i class="bi bi-pencil"></i>
						</button>
						<button class="toolbar-btn danger" id="delete-btn" title="Delete (Del)">
							<i class="bi bi-trash"></i>
						</button>
						<button class="toolbar-btn" id="close-viewer-btn" title="Close Viewer (ESC)">
							<i class="bi bi-x-lg"></i>
						</button>
					</div>
					
					<!-- Slideshow Progress -->
					<div class="slideshow-progress" id="slideshow-progress">
						<div class="progress-bar" id="progress-bar"></div>
					</div>
				</div>
			</div>
		</div>
	</div>

	<!-- Rename Modal -->
	<div class="modal fade" id="renameModal" tabindex="-1">
		<div class="modal-dialog">
			<div class="modal-content">
				<div class="modal-header">
					<h5 class="modal-title">Rename File</h5>
					<button type="button" class="btn-close" data-bs-dismiss="modal"></button>
				</div>
				<div class="modal-body">
					<label class="form-label">New Name</label>
					<input type="text" class="form-control" id="rename-input">
					<small class="text-muted">Extension will be preserved</small>
				</div>
				<div class="modal-footer">
					<button type="button" class="btn btn-secondary" data-bs-dismiss="modal">Cancel</button>
					<button type="button" class="btn btn-primary" id="confirm-rename">Rename</button>
				</div>
			</div>
		</div>
	</div>

	<!-- Delete Confirmation Modal -->
	<div class="modal fade" id="deleteModal" tabindex="-1">
		<div class="modal-dialog">
			<div class="modal-content">
				<div class="modal-header">
					<h5 class="modal-title">Delete File</h5>
					<button type="button" class="btn-close" data-bs-dismiss="modal"></button>
				</div>
				<div class="modal-body">
					<p>Are you sure you want to delete this file?</p>
					<p class="text-muted small" id="delete-filename"></p>
				</div>
				<div class="modal-footer">
					<button type="button" class="btn btn-secondary" data-bs-dismiss="modal">Cancel</button>
					<button type="button" class="btn btn-danger" id="confirm-delete">Delete</button>
				</div>
			</div>
		</div>
	</div>

	<!-- File Info Modal -->
	<div class="modal fade" id="infoModal" tabindex="-1">
		<div class="modal-dialog">
			<div class="modal-content">
				<div class="modal-header">
					<h5 class="modal-title">File Properties</h5>
					<button type="button" class="btn-close" data-bs-dismiss="modal"></button>
				</div>
				<div class="modal-body">
					<div class="file-properties">
						<div class="property-row">
							<span class="property-label">Name:</span>
							<span class="property-value" id="info-name"></span>
						</div>
						<div class="property-row">
							<span class="property-label">Type:</span>
							<span class="property-value" id="info-type"></span>
						</div>
						<div class="property-row">
							<span class="property-label">Size:</span>
							<span class="property-value" id="info-size"></span>
						</div>
						<div class="property-row">
							<span class="property-label">Created:</span>
							<span class="property-value" id="info-created"></span>
						</div>
						<div class="property-row">
							<span class="property-label">Modified:</span>
							<span class="property-value" id="info-modified"></span>
						</div>
						<div class="property-row">
							<span class="property-label">Path:</span>
							<span class="property-value" id="info-path"></span>
						</div>
						<div class="property-row">
							<span class="property-label">Labels:</span>
							<div class="property-value" id="info-labels"></div>
						</div>
					</div>
				</div>
				<div class="modal-footer">
					<button type="button" class="btn btn-secondary" data-bs-dismiss="modal">Close</button>
				</div>
			</div>
		</div>
	</div>



	<!-- Shortcuts Hint -->
	<div class="shortcuts-hint" id="shortcuts-hint">
		<div class="shortcut-row">
			<span><span class="shortcut-key">←/→</span> or <span class="shortcut-key">↑/↓</span> Previous/Next</span>
		</div>
		<div class="shortcut-row">
			<span><span class="shortcut-key">ESC</span> Close viewer</span>
		</div>
		<div class="shortcut-row">
			<span><span class="shortcut-key">F2</span> Rename file</span>
		</div>
		<div class="shortcut-row">
			<span><span class="shortcut-key">DEL</span> Delete file</span>
		</div>
		<div class="shortcut-row">
			<span><span class="shortcut-key">+</span>/<span class="shortcut-key">-</span> Zoom</span>
		</div>
		<div class="shortcut-row">
			<span><span class="shortcut-key">R</span> Rotate image</span>
		</div>
		<div class="shortcut-row">
			<span><span class="shortcut-key">I</span> File info</span>
		</div>
		<div class="shortcut-row">
			<span><span class="shortcut-key">?</span> Toggle hints</span>
		</div>
	</div>

	<!-- Bootstrap -->
	<script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.2/dist/js/bootstrap.bundle.min.js"></script>
	<!-- jQuery v4 -->
	<script src="https://code.jquery.com/jquery-3.7.1.min.js"></script>
	<script src="web.js"></script>
</body>

</html>