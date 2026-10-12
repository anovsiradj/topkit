var Gallery = {
	files: [],
	filtered: [],
	root: '',

	init: function() {
		this.root = $('#root-folder-input').val();
		this.attachEventListeners();
		this.loadFiles();
	},

	loadFiles: function() {
		const self = this;
		$.ajax({
			url: '?list=1&root=' + encodeURIComponent(this.root),
			method: 'GET',
			dataType: 'json',
			success: function(response) {
				if (response.success) {
					self.files = response.data || [];
					List.applyFilters();
				}
			}
		});
	},

	changeRootFolder: function() {
		const self = this;
		const newRoot = $('#root-folder-input').val().trim();
		if (!newRoot) return;
		const $btn = $('#change-root-btn');
		const originalHtml = $btn.html();
		$btn.html('<i class="bi bi-hourglass-split spin"></i>');
		$btn.prop('disabled', true);
		$.ajax({
			url: '?checkdir=1&path=' + encodeURIComponent(newRoot),
			method: 'GET',
			dataType: 'json',
			success: function(response) {
				if (response.exists) {
					self.root = newRoot;
					self.loadFiles();
				} else {
					alert('Directory does not exist or is not accessible: ' + newRoot);
					$('#root-folder-input').focus();
				}
			},
			error: function() {
				alert('Error checking directory. Please verify the path.');
				$('#root-folder-input').focus();
			},
			complete: function() {
				$btn.html(originalHtml);
				$btn.prop('disabled', false);
			}
		});
	},

	attachEventListeners: function() {
		const self = this;
		$('#change-root-btn').on('click', function() { self.changeRootFolder(); });
		$('#root-folder-input').on('keydown', function(e) {
			if (e.key === 'Enter') {
				self.changeRootFolder();
			}
		});
	}
};

$(document).ready(function() {
	Gallery.init();
});
