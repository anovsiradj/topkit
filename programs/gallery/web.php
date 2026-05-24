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
					
					<!-- Search -->
					<div class="input-group input-group-sm" style="width: auto; max-width: 200px;">
						<span class="input-group-text" id="search-label">
							<i class="bi bi-search"></i>
						</span>
						<input type="text" class="form-control" id="search-input" placeholder="Search files..." autocomplete="off" aria-label="Search" aria-describedby="search-label">
					</div>
					
					<!-- Sort -->
					<select class="form-select form-select-sm" id="sort-select" style="width: auto; max-width: 150px;">
						<option value="name">Sort by Name</option>
						<option value="type">Sort by Type</option>
						<option value="size">Sort by Size</option>
						<option value="created_at">Sort by Created</option>
						<option value="modified_at">Sort by Modified</option>
					</select>
					<button class="btn btn-sm btn-outline-secondary" id="sort-direction-btn" title="Sort direction" data-direction="asc">
						<i class="bi bi-sort-up"></i>
					</button>
					<button class="btn btn-sm btn-outline-secondary" id="toggle-shortcuts" title="Keyboard Shortcuts">
						<i class="bi bi-question-circle"></i>
					</button>
				</div>
			</div>
		</div>

		<!-- Main Content -->
		<div class="gallery-content">
			<!-- Sidebar: Labels & Filters -->
			<div class="gallery-sidebar overflow-y-auto">
				<div class="sidebar-section">
					<div class="sidebar-section-title">Filter by Type</div>
					<div class="btn-group-vertical w-100" id="type-filters">
						<button class="btn btn-outline-secondary btn-sm text-start active" data-filter="all">All <span class="float-end badge bg-secondary" id="count-all">0</span></button>
						<button class="btn btn-outline-secondary btn-sm text-start" data-filter="image">Images <span class="float-end badge bg-secondary" id="count-image">0</span></button>
						<button class="btn btn-outline-secondary btn-sm text-start" data-filter="video">Videos <span class="float-end badge bg-secondary" id="count-video">0</span></button>
					</div>
				</div>

				<div class="sidebar-section">
					<div class="sidebar-section-title">Filter By Labels</div>
					<small class="text-muted d-block mb-2">Click to include, Right-click to exclude</small>
					<div id="labels-container" class="tags-cloud"></div>
				</div>
			</div>
			<!-- Main Viewer -->
			<div class="gallery-main">
				<!-- Gallery Grid View (Index/List) -->
				<div class="gallery-grid" id="gallery-grid"></div>

				<!-- Media Viewer (Hidden by default) -->
				<div class="gallery-viewer position-fixed top-0 start-0 w-100 h-100 bg-black bg-opacity-90 z-3" id="viewer-container" style="display: none;">
					<div class="d-flex flex-column h-100">
						<!-- Top Right/Left Controls -->
						<div class="d-flex justify-content-between p-3">
							<span class="bg-dark bg-opacity-75 text-white px-3 py-2 rounded-pill small viewer-counter"></span>
							<div class="d-flex gap-2">
								<span class="bg-dark bg-opacity-75 text-white px-3 py-2 rounded-pill small zoom-indicator" style="display: none;"></span>
								<button type="button" class="btn btn-dark btn-sm bg-opacity-75 border-0" id="close-viewer-btn" title="Close Viewer (ESC)">
									<i class="bi bi-x-lg"></i>
								</button>
							</div>
						</div>

						<!-- Media Content -->
						<div class="flex-grow-1 d-flex align-items-center justify-content-center px-4" id="media-wrapper-container">
							<div class="media-wrapper text-center" id="media-wrapper">
								<div class="empty-state" id="empty-state">
									<i class="bi bi-images"></i>
									<p>No files loaded yet</p>
								</div>
							</div>
						</div>

						<!-- Bottom Toolbar -->
						<div class="p-3">
							<div class="btn-group d-flex justify-content-center gap-1" role="group" id="viewer-toolbar">
								<button type="button" class="btn btn-dark btn-sm bg-opacity-75 border-0" id="prev-btn" title="Previous (Arrow Left)">
									<i class="bi bi-chevron-left"></i>
								</button>
								<button type="button" class="btn btn-dark btn-sm bg-opacity-75 border-0" id="play-btn" title="Play Slideshow (Space)">
									<i class="bi bi-play-fill"></i>
								</button>
								<button type="button" class="btn btn-dark btn-sm bg-opacity-75 border-0" id="next-btn" title="Next (Arrow Right)">
									<i class="bi bi-chevron-right"></i>
								</button>
								<div class="btn-group">
									<button type="button" class="btn btn-dark btn-sm bg-opacity-75 border-0" id="zoom-in-btn" title="Zoom In (+)">
										<i class="bi bi-zoom-in"></i>
									</button>
									<button type="button" class="btn btn-dark btn-sm bg-opacity-75 border-0" id="zoom-out-btn" title="Zoom Out (-)">
										<i class="bi bi-zoom-out"></i>
									</button>
								</div>
								<button type="button" class="btn btn-dark btn-sm bg-opacity-75 border-0" id="rotate-btn" title="Rotate (R)">
									<i class="bi bi-arrow-clockwise"></i>
								</button>
								<button type="button" class="btn btn-dark btn-sm bg-opacity-75 border-0" id="fullscreen-btn" title="Fullscreen (F)">
									<i class="bi bi-fullscreen"></i>
								</button>
								<button type="button" class="btn btn-dark btn-sm bg-opacity-75 border-0" id="info-btn" title="File Info (I)">
									<i class="bi bi-info-circle"></i>
								</button>
								<button type="button" class="btn btn-dark btn-sm bg-opacity-75 border-0" id="rename-btn" title="Rename (F2)">
									<i class="bi bi-pencil"></i>
								</button>
								<button type="button" class="btn btn-danger btn-sm bg-opacity-75 border-0" id="delete-btn" title="Delete (Del)">
									<i class="bi bi-trash"></i>
								</button>
							</div>
						</div>

						<!-- Slideshow Progress -->
						<div class="position-absolute bottom-0 start-0 end-0 slideshow-progress" id="slideshow-progress">
							<div class="progress-bar" id="progress-bar"></div>
						</div>
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

	<!-- Keyboard Shortcuts Modal -->
	<div class="modal fade" id="shortcutsModal" tabindex="-1">
		<div class="modal-dialog">
			<div class="modal-content">
				<div class="modal-header">
					<h5 class="modal-title">Keyboard Shortcuts</h5>
					<button type="button" class="btn-close" data-bs-dismiss="modal"></button>
				</div>
				<div class="modal-body">
					<table class="table table-sm table-borderless">
						<tbody>
							<tr>
								<td class="text-end"><kbd>←</kbd> or <kbd>→</kbd></td>
								<td>Previous/Next in viewer</td>
							</tr>
							<tr>
								<td class="text-end"><kbd>↑</kbd> or <kbd>↓</kbd></td>
								<td>Previous/Next in viewer</td>
							</tr>
							<tr>
								<td class="text-end"><kbd>ESC</kbd></td>
								<td>Close media viewer</td>
							</tr>
							<tr>
								<td class="text-end"><kbd>F2</kbd></td>
								<td>Rename file</td>
							</tr>
							<tr>
								<td class="text-end"><kbd>DEL</kbd></td>
								<td>Delete file</td>
							</tr>
							<tr>
								<td class="text-end"><kbd>+</kbd>/<kbd>-</kbd></td>
								<td>Zoom in/out</td>
							</tr>
							<tr>
								<td class="text-end"><kbd>R</kbd></td>
								<td>Rotate image</td>
							</tr>
							<tr>
								<td class="text-end"><kbd>I</kbd></td>
								<td>File info</td>
							</tr>
							<tr>
								<td class="text-end"><kbd>Space</kbd></td>
								<td>Play/Pause slideshow</td>
							</tr>
							<tr>
								<td class="text-end"><kbd>F</kbd></td>
								<td>Toggle fullscreen</td>
							</tr>
						</tbody>
					</table>
				</div>
				<div class="modal-footer">
					<button type="button" class="btn btn-secondary" data-bs-dismiss="modal">Close</button>
				</div>
			</div>
		</div>
	</div>

	<!-- Bootstrap -->
	<script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.2/dist/js/bootstrap.bundle.min.js"></script>
	<!-- jQuery v4 -->
	<script src="https://code.jquery.com/jquery-3.7.1.min.js"></script>
	<script src="web.js"></script>
	<script src="list.js"></script>
	<script src="view.js"></script>
</body>

</html>