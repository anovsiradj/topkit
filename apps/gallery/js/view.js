var View = {
	currentFile: null,
	currentIndex: 0,
	currentZoom: 1,
	currentRotation: 0,
	panX: 0,
	panY: 0,
	slideshow: {
		active: false,
		timer: null,
		progressInterval: null,
		imageDelay: 3000,
		startTime: null,
		duration: 3000
	},

	openViewer: function(index) {
		this.currentIndex = index;
		this.currentFile = Gallery.filtered[index];
		this.currentRotation = 0;
		this.currentZoom = 1;
		this.panX = 0;
		this.panY = 0;
		this.renderMedia();
		this.updateCounter();
		$('#gallery-grid').hide();
		$('#viewer-container').show();
		if (this.slideshow.active) {
			this.stopSlideshow();
		}
	},

	closeViewer: function() {
		this.currentFile = null;
		$('#viewer-container').hide();
		$('#gallery-grid').show();
		$('#media-wrapper').empty().append(
			'<div class="empty-state" id="empty-state">' +
				'<i class="bi bi-images"></i>' +
				'<p>No files loaded yet</p>' +
			'</div>'
		);
		this.stopSlideshow();
	},

	nextFile: function() {
		if (this.currentIndex < Gallery.filtered.length - 1) {
			this.currentIndex++;
			this.currentFile = Gallery.filtered[this.currentIndex];
			this.currentRotation = 0;
			this.currentZoom = 1;
			this.panX = 0;
			this.panY = 0;
			this.renderMedia();
			this.updateCounter();
			this.updateZoomIndicator();
			if (this.slideshow.active) {
				this.updateProgressBar();
				this.scheduleNextSlide();
			}
		}
	},

	prevFile: function() {
		if (this.currentIndex > 0) {
			this.currentIndex--;
			this.currentFile = Gallery.filtered[this.currentIndex];
			this.currentRotation = 0;
			this.currentZoom = 1;
			this.panX = 0;
			this.panY = 0;
			this.renderMedia();
			this.updateCounter();
			this.updateZoomIndicator();
			if (this.slideshow.active) {
				this.updateProgressBar();
				this.scheduleNextSlide();
			}
		}
	},

	updateCounter: function() {
		let $counter = $('.viewer-counter');
		if ($counter.length === 0) {
			$counter = $('<div class="viewer-counter position-absolute top-3 start-3 bg-dark bg-opacity-75 text-white px-3 py-2 rounded-pill small"></div>');
			$('#viewer-container').append($counter);
		}
		$counter.text((this.currentIndex + 1) + ' / ' + Gallery.filtered.length);
	},

	updateZoomIndicator: function() {
		let $indicator = $('.zoom-indicator');
		if ($indicator.length === 0) {
			$indicator = $('<div class="zoom-indicator position-absolute top-3 start-50 translate-middle-x bg-dark bg-opacity-75 text-white px-3 py-2 rounded-pill small"></div>');
			$('#viewer-container').append($indicator);
		}
		if (this.currentZoom > 1) {
			$indicator.text(Math.round(this.currentZoom * 100) + '%').show();
		} else {
			$indicator.hide();
		}
	},

	zoomIn: function() {
		if (this.currentFile && this.currentFile.type === 'image') {
			this.currentZoom = Math.min(this.currentZoom + 0.2, 5);
			this.renderMedia();
			this.updateZoomIndicator();
		}
	},

	zoomOut: function() {
		if (this.currentFile && this.currentFile.type === 'image') {
			this.currentZoom = Math.max(this.currentZoom - 0.2, 1);
			if (this.currentZoom === 1) {
				$('#media-wrapper img').css({ transform: 'rotate(' + this.currentRotation + 'deg) scale(1)' });
			}
			this.renderMedia();
			this.updateZoomIndicator();
		}
	},

	rotate: function() {
		if (this.currentFile && this.currentFile.type === 'image') {
			this.currentRotation = (this.currentRotation + 90) % 360;
			this.renderMedia();
		}
	},

	renderMedia: function() {
		if (!this.currentFile) return;
		const $wrapper = $('#media-wrapper');
		$wrapper.empty();
		const self = this;

		if (this.currentFile.type === 'image') {
			const $img = $('<img src="' + this.currentFile.url + '" alt="' + this.currentFile.name + '" class="img-fluid" loading="lazy">');
			$img.css({
				transform: 'translate(' + this.panX + 'px, ' + this.panY + 'px) rotate(' + this.currentRotation + 'deg) scale(' + this.currentZoom + ')'
			});
			if (this.currentZoom > 1) {
				$img.addClass('zoomed');
				$img.css({ cursor: 'grab' });
				$img.on('mousedown touchstart', function(e) {
					if (self.currentZoom <= 1) return;
					e.preventDefault();
					const startX = e.clientX || (e.touches && e.touches[0] ? e.touches[0].clientX : 0);
					const startY = e.clientY || (e.touches && e.touches[0] ? e.touches[0].clientY : 0);
					const initialPanX = self.panX;
					const initialPanY = self.panY;
					$img.css({ cursor: 'grabbing' });
					const onMove = function(moveEvent) {
						moveEvent.preventDefault();
						const currentX = moveEvent.clientX || (moveEvent.touches && moveEvent.touches[0] ? moveEvent.touches[0].clientX : 0);
						const currentY = moveEvent.clientY || (moveEvent.touches && moveEvent.touches[0] ? moveEvent.touches[0].clientY : 0);
						self.panX = initialPanX + (currentX - startX);
						self.panY = initialPanY + (currentY - startY);
						$img.css({
							transform: 'translate(' + self.panX + 'px, ' + self.panY + 'px) rotate(' + self.currentRotation + 'deg) scale(' + self.currentZoom + ')'
						});
					};
					const onEnd = function() {
						$img.css({ cursor: 'grab' });
						$(document).off('mousemove touchmove', onMove);
						$(document).off('mouseup touchend', onEnd);
					};
					$(document).on('mousemove touchmove', onMove);
					$(document).on('mouseup touchend', onEnd);
				});
			}
			$wrapper.append($img);
		} else if (this.currentFile.type === 'video') {
			const loopAttr = this.slideshow.active ? '' : 'loop';
			const $video = $(
				'<video controls autoplay ' + loopAttr + ' class="img-fluid">' +
					'<source src="' + this.currentFile.url + '">' +
					'Your browser does not support the video tag.' +
				'</video>'
			);
			if (this.slideshow.active) {
				$video.on('ended', function() {
					if (self.slideshow.active) {
						self.nextFile();
					}
				});
			}
			$wrapper.append($video);
		}
	},

	showRenameDialog: function() {
		if (!this.currentFile) return;
		$('#rename-input').val(this.currentFile.name);
		new bootstrap.Modal($('#renameModal')[0]).show();
	},

	rename: function() {
		if (!this.currentFile) return;
		const newName = $('#rename-input').val().trim();
		if (!newName) return;
		const self = this;
		$.ajax({
			url: '?rename=' + encodeURIComponent(this.currentFile.path) + '&newname=' + encodeURIComponent(newName),
			method: 'POST',
			dataType: 'json',
			success: function(response) {
				if (response.success) {
					bootstrap.Modal.getInstance($('#renameModal')[0]).hide();
					Gallery.loadFiles();
				}
			}
		});
	},

	showDeleteDialog: function() {
		if (!this.currentFile) return;
		$('#delete-filename').text(this.currentFile.name);
		new bootstrap.Modal($('#deleteModal')[0]).show();
	},

	delete: function() {
		if (!this.currentFile) return;
		const self = this;
		$.ajax({
			url: '?delete=' + encodeURIComponent(this.currentFile.path),
			method: 'POST',
			dataType: 'json',
			success: function(response) {
				if (response.success) {
					bootstrap.Modal.getInstance($('#deleteModal')[0]).hide();
					Gallery.loadFiles();
					self.closeViewer();
				}
			}
		});
	},

	showFileInfo: function() {
		if (!this.currentFile) return;
		const file = this.currentFile;
		const createdDate = new Date(file.created_at);
		const modifiedDate = new Date(file.modified_at);
		let sizeText;
		if (file.size >= 1024 * 1024) {
			sizeText = (file.size / (1024 * 1024)).toFixed(2) + ' MB';
		} else if (file.size >= 1024) {
			sizeText = (file.size / 1024).toFixed(1) + ' KB';
		} else {
			sizeText = file.size + ' bytes';
		}
		$('#info-name').text(file.name);
		$('#info-type').text(file.type.toUpperCase());
		$('#info-size').text(sizeText);
		$('#info-created').text(createdDate.toLocaleString());
		$('#info-modified').text(modifiedDate.toLocaleString());
		$('#info-path').text(file.path);
		const $labelsContainer = $('#info-labels');
		$labelsContainer.empty();
		if (file.labels.length > 0) {
			file.labels.forEach(function(label) {
				$labelsContainer.append('<span class="badge bg-secondary me-1 mb-1">' + label + '</span>');
			});
		} else {
			$labelsContainer.text('No labels');
		}
		new bootstrap.Modal($('#infoModal')[0]).show();
	},

	toggleSlideshow: function() {
		if (this.slideshow.active) {
			this.stopSlideshow();
			if (this.currentFile && this.currentFile.type === 'video') {
				this.renderMedia();
			}
		} else {
			this.startSlideshow();
			if (this.currentFile && this.currentFile.type === 'video') {
				this.renderMedia();
			}
		}
	},

	startSlideshow: function() {
		if (Gallery.filtered.length === 0 || !this.currentFile) return;
		this.slideshow.active = true;
		$('#viewer-container').addClass('slideshow-active');
		$('#play-btn').html('<i class="bi bi-pause-fill"></i>');
		$('#play-btn').attr('title', 'Pause Slideshow (Space)');
		this.scheduleNextSlide();
		this.updateProgressBar();
	},

	stopSlideshow: function() {
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

	scheduleNextSlide: function() {
		if (!this.slideshow.active) return;
		if (this.slideshow.timer) {
			clearTimeout(this.slideshow.timer);
		}
		if (this.currentFile.type === 'video') {
			return;
		}
		const self = this;
		this.slideshow.timer = setTimeout(function() {
			if (self.slideshow.active) {
				self.nextFile();
				self.scheduleNextSlide();
			}
		}, this.slideshow.imageDelay);
	},

	updateProgressBar: function() {
		if (!this.slideshow.active) return;
		if (this.slideshow.progressInterval) {
			clearInterval(this.slideshow.progressInterval);
		}
		this.slideshow.startTime = Date.now();
		this.slideshow.duration = this.currentFile.type === 'video' ?
			(this.getVideoDuration() || this.slideshow.imageDelay) :
			this.slideshow.imageDelay;
		const self = this;
		this.slideshow.progressInterval = setInterval(function() {
			if (!self.slideshow.active) {
				clearInterval(self.slideshow.progressInterval);
				return;
			}
			const elapsed = Date.now() - self.slideshow.startTime;
			const progress = Math.min(100, (elapsed / self.slideshow.duration) * 100);
			$('#progress-bar').css('width', progress + '%');
			if (progress >= 100) {
				clearInterval(self.slideshow.progressInterval);
			}
		}, 50);
	},

	getVideoDuration: function() {
		const videoElement = $('#media-wrapper video')[0];
		if (videoElement && videoElement.duration && !isNaN(videoElement.duration)) {
			return videoElement.duration * 1000;
		}
		return null;
	},

	toggleFullscreen: function() {
		if (!document.fullscreenElement) {
			(document.documentElement.requestFullscreen ||
				document.documentElement.webkitRequestFullscreen ||
				document.documentElement.msRequestFullscreen).call(document.documentElement);
		} else {
			(document.exitFullscreen ||
				document.webkitExitFullscreen ||
				document.msExitFullscreen).call(document);
		}
	},

	attachEventListeners: function() {
		const self = this;
		const stopSlideshowIfActive = function() {
			if (self.slideshow.active) {
				self.stopSlideshow();
			}
		};
		$('#next-btn').on('click', function() { stopSlideshowIfActive(); self.nextFile(); });
		$('#prev-btn').on('click', function() { stopSlideshowIfActive(); self.prevFile(); });
		$('#close-viewer-btn').on('click', function() { self.closeViewer(); });
		$('#zoom-in-btn').on('click', function() { stopSlideshowIfActive(); self.zoomIn(); });
		$('#zoom-out-btn').on('click', function() { stopSlideshowIfActive(); self.zoomOut(); });
		$('#rotate-btn').on('click', function() { stopSlideshowIfActive(); self.rotate(); });
		$('#info-btn').on('click', function() { stopSlideshowIfActive(); self.showFileInfo(); });
		$('#rename-btn').on('click', function() { stopSlideshowIfActive(); self.showRenameDialog(); });
		$('#delete-btn').on('click', function() { stopSlideshowIfActive(); self.showDeleteDialog(); });
		$('#play-btn').on('click', function() { self.toggleSlideshow(); });
		$('#fullscreen-btn').on('click', function() { stopSlideshowIfActive(); self.toggleFullscreen(); });
		$('#confirm-rename').on('click', function() { self.rename(); });
		$('#confirm-delete').on('click', function() { self.delete(); });
		$('#toggle-shortcuts').on('click', function() {
			new bootstrap.Modal($('#shortcutsModal')[0]).show();
		});
		$('#viewer-container').on('wheel', function(e) {
			if (!$('#viewer-container').is(':visible')) return;
			if (!self.currentFile || self.currentFile.type !== 'image') return;
			e.preventDefault();
			if (e.originalEvent.deltaY < 0) {
				self.zoomIn();
			} else {
				self.zoomOut();
			}
		});
		$(document).on('keydown', function(e) {
			if ($('#renameModal, #deleteModal, #infoModal, #shortcutsModal').hasClass('show')) return;
			const isViewerOpen = $('#viewer-container').is(':visible');
			if (!isViewerOpen && e.key !== '?') return;
			switch (e.key) {
				case 'ArrowLeft':
					if (isViewerOpen) {
						e.preventDefault();
						self.prevFile();
					}
					break;
				case 'ArrowRight':
					if (isViewerOpen) {
						e.preventDefault();
						self.nextFile();
					}
					break;
				case 'ArrowUp':
					if (isViewerOpen) {
						e.preventDefault();
						self.panY -= 50;
						self.renderMedia();
					}
					break;
				case 'ArrowDown':
					if (isViewerOpen) {
						e.preventDefault();
						self.panY += 50;
						self.renderMedia();
					}
					break;
				case 'Escape':
					if (isViewerOpen) {
						e.preventDefault();
						self.closeViewer();
					}
					break;
				case 'F2':
					if (isViewerOpen) {
						e.preventDefault();
						self.showRenameDialog();
					}
					break;
				case 'Delete':
					if (isViewerOpen) {
						e.preventDefault();
						self.showDeleteDialog();
					}
					break;
				case '+':
				case '=':
					if (isViewerOpen) {
						e.preventDefault();
						self.zoomIn();
					}
					break;
				case '-':
					if (isViewerOpen) {
						e.preventDefault();
						self.zoomOut();
					}
					break;
				case 'r':
				case 'R':
					if (isViewerOpen) {
						e.preventDefault();
						self.rotate();
					}
					break;
				case 'i':
				case 'I':
					if (isViewerOpen) {
						e.preventDefault();
						self.showFileInfo();
					}
					break;
				case '?':
					e.preventDefault();
					new bootstrap.Modal($('#shortcutsModal')[0]).show();
					break;
				case ' ':
					if (isViewerOpen) {
						e.preventDefault();
						self.toggleSlideshow();
					}
					break;
				case 'f':
				case 'F':
					if (isViewerOpen) {
						e.preventDefault();
						self.toggleFullscreen();
					}
					break;
			}
		});
		const viewer = $('#viewer-container');
		let touchStartX = 0;
		let touchStartY = 0;
		const minSwipe = 50;
		viewer.on('touchstart', function(e) {
			touchStartX = e.originalEvent.touches[0].clientX;
			touchStartY = e.originalEvent.touches[0].clientY;
			viewer.addClass('touched');
		});
		viewer.on('touchend', function(e) {
			const deltaX = e.originalEvent.changedTouches[0].clientX - touchStartX;
			const deltaY = e.originalEvent.changedTouches[0].clientY - touchStartY;
			if (Math.abs(deltaX) > Math.abs(deltaY) && Math.abs(deltaX) > 20) {
				e.preventDefault();
			}
			if (Math.abs(deltaX) > minSwipe) {
				if (deltaX < 0) {
					self.nextFile();
				} else {
					self.prevFile();
				}
			}
			setTimeout(function() { viewer.removeClass('touched'); }, 500);
		});
	}
};

$(document).ready(function() {
	View.attachEventListeners();
});
