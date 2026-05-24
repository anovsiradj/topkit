
// ============================================
// Gallery Application
// ============================================

const app = {
	files: [],
	filtered: [],
	currentIndex: 0,
	currentFile: null,
	currentRotation: 0,
	currentZoom: 1,
	activeFilters: { type: 'all', labels: [], search: '' },
	slideshow: {
		active: false,
		timer: null,
		imageDelay: 3000,
		progressInterval: null,
		startTime: null,
		duration: 3000,
	},

	init() {
		// Extract root parameter from URL if present
		const urlParams = new URLSearchParams(window.location.search);
		const rootParam = urlParams.get('root');
		
		// Load files with root parameter if provided
		this.loadFiles(rootParam || null);
		this.attachEventListeners();
		
		// Update the root input field with the parameter value
		if (rootParam) {
			$('#root-folder-input').val(rootParam);
		}
	},

	loadFiles(rootFolder = null) {
		const url = rootFolder ? `?list=1&root=${encodeURIComponent(rootFolder)}` : '?list=1';
		
		$.getJSON(url, (response) => {
			if (response.success) {
				this.files = response.data;
				
				this.renderUI();
				this.applyFilters();
				// Update the root folder input with the actual resolved path
				if (response.data.length > 0) {
					const firstFile = response.data[0];
					const actualRoot = firstFile.path.substring(0, firstFile.path.length - firstFile.name.length - 1);
					$('#root-folder-input').val(actualRoot);
				}
			} else {
				// Handle API error (e.g., show message to user)
			}
		}).fail((jqXHR, textStatus, errorThrown) => {
			// Handle AJAX failure (e.g., show error message to user)
		});
	},

	changeRootFolder() {
		const newRoot = $('#root-folder-input').val().trim();
		if (!newRoot) return;
		
		// Show loading state
		const $btn = $('#change-root-btn');
		const originalHtml = $btn.html();
		$btn.html('<i class="bi bi-hourglass-split"></i>');
		$btn.prop('disabled', true);
		
		// Check if directory exists
		$.ajax({
			url: `?checkdir=1&path=${encodeURIComponent(newRoot)}`,
			method: 'GET',
			dataType: 'json',
			success: (response) => {
				if (response.exists) {
					// Load files from new root
					this.loadFiles(newRoot);
					// Update URL with new root parameter
					const url = new URL(window.location);
					url.searchParams.set('root', newRoot);
					window.history.pushState({}, '', url);
				} else {
					alert('Directory does not exist or is not accessible.');
					$('#root-folder-input').focus();
				}
			},
			error: () => {
				alert('Error checking directory. Please verify the path.');
				$('#root-folder-input').focus();
			},
			complete: () => {
				$btn.html(originalHtml);
				$btn.prop('disabled', false);
			}
		});
	},

	renderUI() {
		this.renderLabels();
		this.renderGalleryGrid();
		$('#file-count').text(`${this.files.length} items`);
	},

	renderLabels() {
		const labels = {};
		
		// Count files per label
		this.files.forEach(file => {
			file.labels.forEach(label => {
				labels[label] = (labels[label] || 0) + 1;
			});
		});

		const $container = $('#labels-container');
		$container.empty();

		if (Object.keys(labels).length === 0) {
			$container.html('<small class="text-muted">No labels</small>');
			return;
		}

		// Sort by count (descending)
		const sorted = Object.entries(labels).sort((a, b) => b[1] - a[1]);
		
		// Calculate size classes based on count distribution
		const counts = sorted.map(([_, count]) => count);
		const maxCount = Math.max(...counts);
		const minCount = Math.min(...counts);
		
		sorted.forEach(([label, count]) => {
			const isActive = this.activeFilters.labels.includes(label);
			
			// Calculate size class (1-5) based on count
			let sizeClass = 1;
			if (maxCount > minCount) {
				const normalized = (count - minCount) / (maxCount - minCount);
				sizeClass = Math.min(5, Math.max(1, Math.ceil(normalized * 5)));
			}
			
			const $tag = $(`
				<div class="tag-item size-${sizeClass} ${isActive ? 'active' : ''}" data-label="${label}">
					<span>${label}</span>
					<span class="tag-count">${count}</span>
				</div>
			`);
			$tag.on('click', () => this.toggleLabelFilter(label));
			$container.append($tag);
		});
	},

	renderGalleryGrid() {
		const $grid = $('#gallery-grid');
		$grid.empty();

		if (this.filtered.length === 0) {
			$grid.html('<div class="col-12 text-center text-muted py-5"><i class="bi bi-inbox fs-1 mb-3 d-block"></i>No files match filters</div>');
			return;
		}
		
		// Create a row for the grid
		const $row = $('<div class="row g-3"></div>');
		
		this.filtered.forEach((file, idx) => {
			const $card = $(`
				<div class="col-3">
					<div class="file-card h-100" data-index="${idx}">
						<div class="ratio ratio-4x3 bg-dark">
							${file.type === 'image' ? `<img src="${file.url}" alt="${file.name}" class="img-fluid object-fit-cover" loading="lazy">` : `<div class="d-flex align-items-center justify-content-center"><i class="bi bi-film fs-1 text-muted"></i></div>`}
						</div>
						<div class="file-card-info">
							<div class="file-card-name" title="${file.name}">${file.name}</div>
							<div class="file-card-meta">${(file.size / 1024).toFixed(1)} KB</div>
							<div class="file-card-type">${file.type}</div>
						</div>
					</div>
				</div>
			`);
			$card.find('.file-card').on('click', () => this.openViewer(idx));
			$row.append($card);
		});
		
		$grid.append($row);
	},





	toggleLabelFilter(label) {
		const idx = this.activeFilters.labels.indexOf(label);
		if (idx > -1) {
			this.activeFilters.labels.splice(idx, 1);
		} else {
			this.activeFilters.labels.push(label);
		}
		this.applyFilters();
	},

	applyFilters() {
		this.filtered = this.files.filter(file => {
			// Type filter
			if (this.activeFilters.type !== 'all' && file.type !== this.activeFilters.type) {
				return false;
			}

			// Search filter
			if (this.activeFilters.search) {
				if (!file.name.toLowerCase().includes(this.activeFilters.search.toLowerCase())) {
					return false;
				}
			}

			// Label filter - if labels selected, show only files that have all selected labels
			if (this.activeFilters.labels.length > 0) {
				const hasAllLabels = this.activeFilters.labels.every(label =>
					file.labels.includes(label)
				);
				if (!hasAllLabels) return false;
			}

			return true;
		});

		// Apply sorting
		const sortBy = $('#sort-select').val();
		this.sorted(sortBy);

		this.renderGalleryGrid();
		this.renderLabels();
		if (this.currentFile && !this.filtered.includes(this.currentFile)) {
			this.closeViewer();
		}
	},

	sorted(sortBy) {
		this.filtered.sort((a, b) => {
			switch (sortBy) {
				case 'name':
					return a.name.localeCompare(b.name);
				case 'type':
					return a.type.localeCompare(b.type);
				case 'size':
					return a.size - b.size;
				case 'created_at':
					return a.created_at - b.created_at;
				case 'modified_at':
					return a.modified_at - b.modified_at;
				default:
					return 0;
			}
		});
	},

	zoomIn() {
		if (this.currentFile?.type === 'image') {
			this.currentZoom = Math.min(this.currentZoom + 0.2, 5);
			this.renderMediaViewer();
		}
	},

	zoomOut() {
		if (this.currentFile?.type === 'image') {
			this.currentZoom = Math.max(this.currentZoom - 0.2, 1);
			if (this.currentZoom === 1) {
				// Reset any drag translation when zoom is back to 1
				const $img = $('#media-wrapper img');
				$img.css({
					transform: `rotate(${this.currentRotation}deg) scale(1)`
				});
			}
			this.renderMediaViewer();
		}
	},

	rotate() {
		if (this.currentFile?.type === 'image') {
			this.currentRotation = (this.currentRotation + 90) % 360;
			this.renderMediaViewer();
		}
	},

	showRenameDialog() {
		if (!this.currentFile) return;
		const nameWithoutExt = this.currentFile.name.substring(0, this.currentFile.name.lastIndexOf('.'));
		$('#rename-input').val(nameWithoutExt);
		new bootstrap.Modal($('#renameModal')[0]).show();
	},

	rename() {
		if (!this.currentFile) return;
		const newName = $('#rename-input').val().trim();
		if (!newName) return;

		$.ajax({
			url: '?rename=' + encodeURIComponent(this.currentFile.path) + '&newname=' + encodeURIComponent(newName),
			method: 'POST',
			dataType: 'json',
			success: (response) => {
				if (response.success) {
					bootstrap.Modal.getInstance($('#renameModal')[0]).hide();
					this.loadFiles();
				}
			}
		});
	},

	showDeleteDialog() {
		if (!this.currentFile) return;
		$('#delete-filename').text(this.currentFile.name);
		new bootstrap.Modal($('#deleteModal')[0]).show();
	},

	delete() {
		if (!this.currentFile) return;

		$.ajax({
			url: '?delete=' + encodeURIComponent(this.currentFile.path),
			method: 'POST',
			dataType: 'json',
			success: (response) => {
				if (response.success) {
					bootstrap.Modal.getInstance($('#deleteModal')[0]).hide();
					this.loadFiles();
				}
			}
		});
	},

	showFileInfo() {
		if (!this.currentFile) return;
		
		const file = this.currentFile;
		const createdDate = new Date(file.created_at);
		const modifiedDate = new Date(file.modified_at);
		
		// Format file size
		let sizeText;
		if (file.size >= 1024 * 1024) {
			sizeText = (file.size / (1024 * 1024)).toFixed(2) + ' MB';
		} else if (file.size >= 1024) {
			sizeText = (file.size / 1024).toFixed(1) + ' KB';
		} else {
			sizeText = file.size + ' bytes';
		}
		
		// Update modal content
		$('#info-name').text(file.name);
		$('#info-type').text(file.type.toUpperCase() + ' (' + file.mime + ')');
		$('#info-size').text(sizeText);
		$('#info-created').text(createdDate.toLocaleString());
		$('#info-modified').text(modifiedDate.toLocaleString());
		$('#info-path').text(file.path);
		
		// Update labels
		const $labelsContainer = $('#info-labels');
		$labelsContainer.empty();
		if (file.labels.length > 0) {
			file.labels.forEach(label => {
				$labelsContainer.append(`<span>${label}</span>`);
			});
		} else {
			$labelsContainer.text('No labels');
		}
		
		// Show modal
		new bootstrap.Modal($('#infoModal')[0]).show();
	},

	attachEventListeners() {
		// Type filters
		$('#type-filters').on('click', '.filter-btn', (e) => {
			$('.filter-btn').removeClass('active');
			$(e.target).closest('.filter-btn').addClass('active');
			this.activeFilters.type = $(e.target).closest('.filter-btn').data('filter');
			this.applyFilters();
		});

		// Search
		$('#search-input').on('input', (e) => {
			this.activeFilters.search = e.target.value;
			this.applyFilters();
		});

		// Sort
		$('#sort-select').on('change', () => {
			this.applyFilters();
		});



		// Navigation
		$('#next-btn').on('click', () => this.nextFile());
		$('#prev-btn').on('click', () => this.prevFile());

		// Close viewer
		$('#close-viewer-btn').on('click', () => this.closeViewer());

		// Viewer controls
		$('#zoom-in-btn').on('click', () => this.zoomIn());
		$('#zoom-out-btn').on('click', () => this.zoomOut());
		$('#rotate-btn').on('click', () => this.rotate());
		$('#info-btn').on('click', () => this.showFileInfo());
		$('#rename-btn').on('click', () => this.showRenameDialog());
		$('#delete-btn').on('click', () => this.showDeleteDialog());

		// Modal actions
		$('#confirm-rename').on('click', () => this.rename());
		$('#confirm-delete').on('click', () => this.delete());

		// Keyboard shortcuts
		$(document).on('keydown', (e) => {
			if ($('#renameModal, #deleteModal').hasClass('show')) return;

			const isViewerOpen = $('#viewer-container').is(':visible');

			switch (e.key) {
				case 'ArrowLeft':
				case 'ArrowUp':
					if (isViewerOpen) {
						e.preventDefault();
						this.prevFile();
					}
					break;
				case 'ArrowRight':
				case 'ArrowDown':
					if (isViewerOpen) {
						e.preventDefault();
						this.nextFile();
					}
					break;
				case 'Escape':
					if (isViewerOpen) {
						e.preventDefault();
						this.closeViewer();
					}
					break;
				case 'F2':
					if (isViewerOpen) {
						e.preventDefault();
						this.showRenameDialog();
					}
					break;
				case 'Delete':
					if (isViewerOpen) {
						e.preventDefault();
						this.showDeleteDialog();
					}
					break;
				case '+':
				case '=':
					if (isViewerOpen) {
						e.preventDefault();
						this.zoomIn();
					}
					break;
				case '-':
					e.preventDefault();
					if (isViewerOpen) {
						this.zoomOut();
					}
					break;
				case 'r':
				case 'R':
					if (isViewerOpen) {
						e.preventDefault();
						this.rotate();
					}
					break;
				case 'i':
				case 'I':
					if (isViewerOpen) {
						e.preventDefault();
						this.showFileInfo();
					}
					break;
				case '?':
					e.preventDefault();
					$('#shortcuts-hint').toggleClass('visible');
					break;
				case ' ':
					if (isViewerOpen) {
						e.preventDefault();
						this.toggleSlideshow();
					}
					break;
				case 'f':
				case 'F':
					if (isViewerOpen) {
						e.preventDefault();
						this.toggleFullscreen();
					}
					break;
			}
		});

		// Shortcuts hint toggle
		$('#toggle-shortcuts').on('click', () => {
			$('#shortcuts-hint').toggleClass('visible');
		});

		// Root folder change
		$('#change-root-btn').on('click', () => this.changeRootFolder());
		$('#root-folder-input').on('keydown', (e) => {
			if (e.key === 'Enter') {
				this.changeRootFolder();
			}
		});
		
		// Slideshow controls
		$('#play-btn').on('click', () => this.toggleSlideshow());
		$('#fullscreen-btn').on('click', () => this.toggleFullscreen());
	},
	
	// Slideshow methods
	toggleSlideshow() {
		if (this.slideshow.active) {
			this.stopSlideshow();
			// Refresh viewer to update video loop behavior
			if (this.currentFile && this.currentFile.type === 'video') {
				this.renderMediaViewer();
			}
		} else {
			this.startSlideshow();
			// Refresh viewer to update video loop behavior
			if (this.currentFile && this.currentFile.type === 'video') {
				this.renderMediaViewer();
			}
		}
	},
	
	startSlideshow() {
		if (this.filtered.length === 0 || !this.currentFile) return;
		
		this.slideshow.active = true;
		$('#viewer-container').addClass('slideshow-active');
		$('#play-btn').html('<i class="bi bi-pause-fill"></i>');
		$('#play-btn').attr('title', 'Pause Slideshow (Space)');
		
		this.scheduleNextSlide();
		this.updateProgressBar();
	},
	
	stopSlideshow() {
		this.slideshow.active = false;
		$('#viewer-container').removeClass('slideshow-active');
		$('#play-btn').html('<i class="bi bi-play-fill"></i>');
		$('#play-btn').attr('title', 'Play Slideshow (Space)');
		
		if (this.slideshow.timer) {
			clearTimeout(this.slideshow.timer);
			this.slideshow.timer = null;
		}
		
		if (this.slideshow.progressInterval) {
			clearInterval(this.slideshow.progressInterval);
			this.slideshow.progressInterval = null;
		}
		
		$('#progress-bar').css('width', '0%');
	},
	
	scheduleNextSlide() {
		if (!this.slideshow.active) return;
		
		if (this.slideshow.timer) {
			clearTimeout(this.slideshow.timer);
		}
		
		const currentFile = this.currentFile;
		
		// For videos in slideshow mode, we don't schedule a timer
		// The video will autoplay (without loop) and the onended event listener
		// in renderMediaViewer() will handle transitioning to the next file
		if (currentFile.type === 'video') {
			return;
		}
		
		// For images, schedule the next slide after the delay
		this.slideshow.timer = setTimeout(() => {
			if (this.slideshow.active) {
				this.nextFile();
				this.scheduleNextSlide();
			}
		}, this.slideshow.imageDelay);
	},
	
	updateProgressBar() {
		if (!this.slideshow.active) return;
		
		if (this.slideshow.progressInterval) {
			clearInterval(this.slideshow.progressInterval);
		}
		
		this.slideshow.startTime = Date.now();
		this.slideshow.duration = this.currentFile.type === 'video' ? 
			(this.getVideoDuration() || this.slideshow.imageDelay) : 
			this.slideshow.imageDelay;
		
		this.slideshow.progressInterval = setInterval(() => {
			if (!this.slideshow.active) {
				clearInterval(this.slideshow.progressInterval);
				return;
			}
			
			const elapsed = Date.now() - this.slideshow.startTime;
			const progress = Math.min(100, (elapsed / this.slideshow.duration) * 100);
			$('#progress-bar').css('width', progress + '%');
			
			if (progress >= 100) {
				clearInterval(this.slideshow.progressInterval);
			}
		}, 50);
	},
	
	getVideoDuration() {
		const videoElement = $('#media-wrapper video')[0];
		if (videoElement && videoElement.duration && !isNaN(videoElement.duration)) {
			return videoElement.duration * 1000; // Convert to milliseconds
		}
		return null;
	},
	
	// Fullscreen methods
	toggleFullscreen() {
		const viewerContainer = $('#viewer-container')[0];
		
		if (!document.fullscreenElement) {
			if (viewerContainer.requestFullscreen) {
				viewerContainer.requestFullscreen();
			} else if (viewerContainer.webkitRequestFullscreen) {
				viewerContainer.webkitRequestFullscreen();
			} else if (viewerContainer.msRequestFullscreen) {
				viewerContainer.msRequestFullscreen();
			}
		} else {
			if (document.exitFullscreen) {
				document.exitFullscreen();
			} else if (document.webkitExitFullscreen) {
				document.webkitExitFullscreen();
			} else if (document.msExitFullscreen) {
				document.msExitFullscreen();
			}
		}
	},
	
	// Update openViewer to handle slideshow
	openViewer(index) {
		this.currentIndex = index;
		this.currentFile = this.filtered[index];
		this.currentRotation = 0;
		this.currentZoom = 1;

		this.renderMediaViewer();
		$('#gallery-grid').hide();
		$('#viewer-container').show();
		
		// Stop slideshow if it was running
		if (this.slideshow.active) {
			this.stopSlideshow();
		}
	},
	
	// Update closeViewer to stop slideshow
	closeViewer() {
		this.currentFile = null;
		$('#viewer-container').hide();
		$('#gallery-grid').show();
		$('#media-wrapper').empty().append('<div class="empty-state" id="empty-state"><i class="bi bi-images"></i><p>No files loaded yet</p></div>');
		
		// Stop slideshow
		this.stopSlideshow();
	},
	
	// Update nextFile and prevFile to handle slideshow
	nextFile() {
		if (this.currentIndex < this.filtered.length - 1) {
			this.currentIndex++;
			this.currentFile = this.filtered[this.currentIndex];
			this.currentRotation = 0;
			this.currentZoom = 1;
			this.renderMediaViewer();
			
			// Reset progress bar and schedule next slide if slideshow is active
			if (this.slideshow.active) {
				this.updateProgressBar();
				this.scheduleNextSlide();
			}
		}
	},
	
	prevFile() {
		if (this.currentIndex > 0) {
			this.currentIndex--;
			this.currentFile = this.filtered[this.currentIndex];
			this.currentRotation = 0;
			this.currentZoom = 1;
			this.renderMediaViewer();
			
			// Reset progress bar and schedule next slide if slideshow is active
			if (this.slideshow.active) {
				this.updateProgressBar();
				this.scheduleNextSlide();
			}
		}
	},
	
	// Update renderMediaViewer to handle video autoplay in slideshow
	renderMediaViewer() {
		if (!this.currentFile) return;

		const $wrapper = $('#media-wrapper');
		$wrapper.empty();

		const date = new Date(this.currentFile.modified_at);
		const sizeMB = (this.currentFile.size / (1024 * 1024)).toFixed(2);
		const sizeKB = (this.currentFile.size / 1024).toFixed(1);

		if (this.currentFile.type === 'image') {
			const $img = $(`<img src="${this.currentFile.url}" alt="${this.currentFile.name}" loading="lazy">`);
			$img.css({
				transform: `rotate(${this.currentRotation}deg) scale(${this.currentZoom})`
			});
			
			if (this.currentZoom > 1) {
				$img.addClass('zoomed');
				$img.on('mousedown touchstart', (e) => {
					if (this.currentZoom <= 1) return;
					
					const startX = e.clientX || e.touches[0].clientX;
					const startY = e.clientY || e.touches[0].clientY;
					const startTransform = $img.css('transform');
					
					const onMove = (moveEvent) => {
						moveEvent.preventDefault();
						const currentX = moveEvent.clientX || moveEvent.touches[0].clientX;
						const currentY = moveEvent.clientY || moveEvent.touches[0].clientY;
						
						const deltaX = currentX - startX;
						const deltaY = currentY - startY;
						
						// Apply translation based on drag
						$img.css({
							transform: `${startTransform} translate(${deltaX}px, ${deltaY}px)`
						});
					};
					
					const onEnd = () => {
						$(document).off('mousemove touchmove', onMove);
						$(document).off('mouseup touchend', onEnd);
					};
					
					$(document).on('mousemove touchmove', onMove);
					$(document).on('mouseup touchend', onEnd);
				});
			}
			
			$wrapper.append($img);
		} else if (this.currentFile.type === 'video') {
			// In slideshow mode: autoplay but don't loop (continue to next file after video ends)
			// In normal mode: autoplay and loop
			const autoplay = 'autoplay';
			const loop = this.slideshow.active ? '' : 'loop';
			const $video = $(`<video controls ${autoplay} ${loop} style="max-width: 100%; max-height: 100%;">
				<source src="${this.currentFile.url}">
				Your browser does not support the video tag.
			</video>`);
			
			// Add event listener for video end in slideshow mode
			if (this.slideshow.active) {
				$video.on('ended', () => {
					if (this.slideshow.active) {
						this.nextFile();
					}
				});
			}
			
			$wrapper.append($video);
		}

		// Add media info overlay
		const $info = $(`
			<div class="media-info">
				<div class="media-info-title">${this.currentFile.name}</div>
				<div class="media-info-meta">
					<span>${this.currentFile.type.toUpperCase()}</span>
					<span>${sizeMB > 0.1 ? `${sizeMB} MB` : `${sizeKB} KB`}</span>
					<span>${date.toLocaleDateString()}</span>
				</div>
				${this.currentFile.labels.length > 0 ? `
					<div class="media-info-labels">
						${this.currentFile.labels.map(label => `<span class="media-info-label">${label}</span>`).join('')}
					</div>
				` : ''}
			</div>
		`);
		
		$wrapper.append($info);
	},

};

// Initialize on document ready
$(document).ready(() => {
	app.init();
});
