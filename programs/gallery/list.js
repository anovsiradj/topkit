var List = {
	activeFilters: {
		type: 'all',
		search: '',
		includeLabels: [],
		excludeLabels: []
	},
	sortDirection: 'asc',

	render: function() {
		this.renderTypeCounts();
		this.renderLabels();
		this.renderGrid();
	},

	renderTypeCounts: function() {
		const counts = {
			all: Gallery.files.length,
			image: 0,
			video: 0
		};
		Gallery.files.forEach(function(file) {
			counts[file.type]++;
		});
		$('#count-all').text(counts.all);
		$('#count-image').text(counts.image);
		$('#count-video').text(counts.video);
	},

	renderLabels: function() {
		const labels = {};
		Gallery.files.forEach(function(file) {
			file.labels.forEach(function(label) {
				labels[label] = (labels[label] || 0) + 1;
			});
		});
		const $container = $('#labels-container');
		$container.empty();
		if (Object.keys(labels).length === 0) {
			$container.html('<small class="text-muted">No labels</small>');
			return;
		}
		const sorted = Object.entries(labels).sort(function(a, b) { return b[1] - a[1]; });
		const counts = sorted.map(function([_, count]) { return count; });
		const maxCount = Math.max.apply(Math, counts);
		const minCount = Math.min.apply(Math, counts);
		const self = this;
		sorted.forEach(function([label, count]) {
			let stateClass = '';
			if (self.activeFilters.includeLabels.indexOf(label) > -1) {
				stateClass = ' active';
			} else if (self.activeFilters.excludeLabels.indexOf(label) > -1) {
				stateClass = ' exclude';
			}
			let sizeClass = 1;
			if (maxCount > minCount) {
				const normalized = (count - minCount) / (maxCount - minCount);
				sizeClass = Math.min(5, Math.max(1, Math.ceil(normalized * 5)));
			}
			const $tag = $('<div class="tag-item size-' + sizeClass + stateClass + '" data-label="' + label + '"><span>' + label + '</span><span class="tag-count">' + count + '</span></div>');
			$tag.on('click', function() { self.toggleLabelFilter(label, false); });
			$tag.on('contextmenu', function(e) {
				e.preventDefault();
				self.toggleLabelFilter(label, true);
			});
			$container.append($tag);
		});
	},

	toggleLabelFilter: function(label, exclude) {
		const includeIdx = this.activeFilters.includeLabels.indexOf(label);
		const excludeIdx = this.activeFilters.excludeLabels.indexOf(label);

		if (exclude) {
			if (excludeIdx > -1) {
				this.activeFilters.excludeLabels.splice(excludeIdx, 1);
			} else {
				if (includeIdx > -1) {
					this.activeFilters.includeLabels.splice(includeIdx, 1);
				}
				this.activeFilters.excludeLabels.push(label);
			}
		} else {
			if (includeIdx > -1) {
				this.activeFilters.includeLabels.splice(includeIdx, 1);
			} else {
				if (excludeIdx > -1) {
					this.activeFilters.excludeLabels.splice(excludeIdx, 1);
				}
				this.activeFilters.includeLabels.push(label);
			}
		}

		this.applyFilters();
	},

	applyFilters: function() {
		const self = this;
		Gallery.filtered = Gallery.files.filter(function(file) {
			if (self.activeFilters.type !== 'all' && file.type !== self.activeFilters.type) {
				return false;
			}
			if (self.activeFilters.search) {
				if (!file.name.toLowerCase().includes(self.activeFilters.search.toLowerCase())) {
					return false;
				}
			}
			if (self.activeFilters.includeLabels.length > 0) {
				const hasAllIncludeLabels = self.activeFilters.includeLabels.every(function(label) {
					return file.labels.indexOf(label) > -1;
				});
				if (!hasAllIncludeLabels) return false;
			}
			if (self.activeFilters.excludeLabels.length > 0) {
				const hasAnyExcludeLabel = self.activeFilters.excludeLabels.some(function(label) {
					return file.labels.indexOf(label) > -1;
				});
				if (hasAnyExcludeLabel) return false;
			}
			return true;
		});
		this.sorted($('#sort-select').val());
		this.renderGrid();
		this.renderLabels();
		if (View.currentFile && Gallery.filtered.indexOf(View.currentFile) === -1) {
			View.closeViewer();
		}
	},

	sorted: function(sortBy) {
		const multiplier = this.sortDirection === 'asc' ? 1 : -1;
		Gallery.filtered.sort(function(a, b) {
			let compare;
			switch (sortBy) {
				case 'name': 
					compare = a.name.localeCompare(b.name);
					break;
				case 'type': 
					compare = a.type.localeCompare(b.type);
					break;
				case 'size': 
					compare = a.size - b.size;
					break;
				case 'created_at': 
					compare = a.created_at - b.created_at;
					break;
				case 'modified_at': 
					compare = a.modified_at - b.modified_at;
					break;
				default: 
					return 0;
			}
			return compare * multiplier;
		});
	},

	renderGrid: function() {
		const $grid = $('#gallery-grid');
		$grid.empty();
		if (Gallery.filtered.length === 0) {
			$grid.html('<div class="col-12 text-center text-muted py-5"><i class="bi bi-inbox fs-1 mb-3 d-block"></i>No files match filters</div>');
			return;
		}
		const $row = $('<div class="row g-3"></div>');
		const self = this;
		Gallery.filtered.forEach(function(file, idx) {
			const $card = $(
				'<div class="col-6 col-md-4 col-lg-3">' +
					'<div class="file-card h-100" data-index="' + idx + '">' +
						'<div class="ratio ratio-4x3 bg-dark">' +
							(file.type === 'image' ?
								'<img src="' + file.url + '" alt="' + file.name + '" class="img-fluid object-fit-cover" loading="lazy">' :
								'<div class="d-flex align-items-center justify-content-center">' +
									'<i class="bi bi-film fs-1 text-muted"></i>' +
								'</div>'
							) +
						'</div>' +
						'<div class="file-card-info">' +
							'<div class="file-card-name" title="' + file.name + '">' + file.name + '</div>' +
						'</div>' +
					'</div>' +
				'</div>'
			);
			$card.find('.file-card').on('click', function() { View.openViewer(idx); });
			$row.append($card);
		});
		$grid.append($row);
	},

	attachEventListeners: function() {
		const self = this;
		$('#type-filters').on('click', 'button', function(e) {
			$('#type-filters button').removeClass('btn-secondary active');
			$('#type-filters button').addClass('btn-outline-secondary');
			const $btn = $(e.target).closest('button');
			$btn.removeClass('btn-outline-secondary');
			$btn.addClass('btn-secondary active');
			self.activeFilters.type = $btn.data('filter');
			self.applyFilters();
		});
		$('#search-input').on('input', function(e) {
			self.activeFilters.search = e.target.value;
			self.applyFilters();
		});
		$('#sort-select').on('change', function() {
			self.applyFilters();
		});
		$('#sort-direction-btn').on('click', function() {
			self.sortDirection = self.sortDirection === 'asc' ? 'desc' : 'asc';
			$(this).attr('data-direction', self.sortDirection);
			$(this).html(self.sortDirection === 'asc' ? '<i class="bi bi-sort-up"></i>' : '<i class="bi bi-sort-down"></i>');
			self.applyFilters();
		});
	}
};

$(document).ready(function() {
	List.attachEventListeners();
});
