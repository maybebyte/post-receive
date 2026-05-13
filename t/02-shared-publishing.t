#!/usr/bin/env perl
use strict;
use warnings;

use English qw(-no_match_vars);
use File::Basename qw(dirname);
use Readonly;
use File::Spec;
use File::Spec::Functions qw(catdir catfile rootdir);
use Test::More;
use lib File::Spec->catdir( dirname( File::Spec->rel2abs(__FILE__) ), 'lib' );

use PostReceive::TestHarness;

Readonly::Scalar my $EXECUTABLE_MODE => oct '0700';
Readonly::Scalar my $GZIP_THRESHOLD_BYTES => 1_400;
Readonly::Scalar my $LARGE_FIXTURE_BYTES => 1_501;
Readonly::Scalar my $PNG_PAYLOAD_FILL_BYTES => 1_700;
Readonly::Scalar my $STYLE_CSS_RULE_REPEAT_COUNT => 32;
Readonly::Scalar my $HTML_SYNC_SKIP_COUNT => 3;
Readonly::Scalar my $COPIED_ASSETS_SKIP_COUNT => 3;
Readonly::Scalar my $STAGIT_TRACE_SKIP_COUNT => 2;
Readonly::Scalar my $PNG_SIGNATURE_HEX => '89504e470d0a1a0a';

sub png_fixture_bytes {
	my ($suffix) = @_;

	my $signature = pack q{H*}, $PNG_SIGNATURE_HEX;
	return $signature . $suffix;
}

sub setup_or_return {
	my ( $label, $code, $harness ) = @_;

	my $value = eval { $code->() };
	if ( !$EVAL_ERROR ) {
		pass($label);
		return $value;
	}

	fail($label);
	diag($EVAL_ERROR);
	diag( $harness->describe_workspace );
	return;
}

sub ok_with_diag {
	my ( $bool, $label, $diag ) = @_;
	ok( $bool, $label ) or diag($diag);
	return $bool;
}

sub is_with_diag {
	my ( $got, $expected, $label, $diag ) = @_;
	is( $got, $expected, $label ) or diag($diag);
	return;
}

sub like_with_diag {
	my ( $got, $pattern, $label, $diag ) = @_;
	like( $got, $pattern, $label ) or diag($diag);
	return;
}

sub unlike_with_diag {
	my ( $got, $pattern, $label, $diag ) = @_;
	unlike( $got, $pattern, $label ) or diag($diag);
	return;
}

sub perl_single_quote {
	my ($text) = @_;

	$text =~ s{\\}{\\\\}g;
	$text =~ s{'}{\\'}g;

	return "'$text'";
}

sub install_fake_stagit_matrix {
	my ($harness) = @_;

	my $fake = $harness->install_fake_stagit;
	my $trace_literal = perl_single_quote( $fake->{trace_path} );
	my $large_fixture_bytes = $LARGE_FIXTURE_BYTES;
	my $gzip_threshold_bytes = $GZIP_THRESHOLD_BYTES;
	my $png_payload_fill_bytes = $PNG_PAYLOAD_FILL_BYTES;
	my $png_signature_hex = $PNG_SIGNATURE_HEX;

	my $script = <<"FAKE_STAGIT";
#!/usr/bin/env perl
use strict;
use warnings;
use Cwd qw(getcwd);
use File::Path qw(make_path);

sub write_text {
	my ( \$path, \$content ) = \@_;
	open my \$fh, '>', \$path
		or die "Could not open \$path for writing: \$!\\n";
	print {\$fh} \$content
		or die "Could not write to \$path: \$!\\n";
	close \$fh
		or die "Could not close \$path: \$!\\n";
}

sub write_binary {
	my ( \$path, \$content ) = \@_;
	open my \$fh, '>', \$path
		or die "Could not open \$path for writing: \$!\\n";
	binmode \$fh or die "Could not enable binmode for \$path: \$!\\n";
	print {\$fh} \$content
		or die "Could not write to \$path: \$!\\n";
	close \$fh
		or die "Could not close \$path: \$!\\n";
}

sub write_exact_text {
	my ( \$path, \$prefix, \$size, \$fill ) = \@_;
	my \$remaining = \$size - length \$prefix;
	die "Prefix for \$path exceeds requested size of \$size bytes\\n"
		if \$remaining < 0;
	write_text( \$path, \$prefix . ( \$fill x \$remaining ) );
}

my \$trace_path = $trace_literal;

open my \$trace_fh, '>', \$trace_path
	or die "Could not open \$trace_path for writing: \$!\\n";
print {\$trace_fh} "cwd=", getcwd(), "\\n";
for my \$index ( 0 .. \$#ARGV ) {
	print {\$trace_fh} "argv[\$index]=", \$ARGV[\$index], "\\n";
}
close \$trace_fh
	or die "Could not close \$trace_path: \$!\\n";

my \$repo = \@ARGV ? \$ARGV[-1] : q{};
my \$large = $large_fixture_bytes;
my \$small = $gzip_threshold_bytes;
my \$png_signature = pack q{H*}, '$png_signature_hex';

write_exact_text(
	'log.html',
	"<!doctype html>\\n<title>fake stagit</title>\\n<p>\$repo</p>\\n",
	\$large,
	'L',
);
write_exact_text(
	'page-small.html',
	"<!doctype html>\\n<title>small html</title>\\n<p>\$repo</p>\\n",
	\$small,
	'h',
);
write_exact_text(
	'tiny.css',
	"/* small css for \$repo */\\n",
	\$small,
	'c',
);
write_exact_text(
	'notes.txt',
	"large text payload for \$repo\\n",
	\$large,
	't',
);
write_exact_text(
	'tiny.txt',
	"small text payload for \$repo\\n",
	\$small,
	'u',
);
write_exact_text(
	'feed.xml',
	'<?xml version="1.0"?>' . "\\n" . '<feed repo="' . \$repo . '">' . "\\n",
	\$large,
	'x',
);
write_exact_text(
	'tiny.xml',
	'<?xml version="1.0"?>' . "\\n" . '<feed>' . "\\n",
	\$small,
	'y',
);
write_exact_text(
	'release.asc',
	"-----BEGIN PGP SIGNATURE-----\\nrepo=\$repo\\n",
	\$large,
	'a',
);
write_exact_text(
	'tiny.asc',
	"-----BEGIN PGP SIGNATURE-----\\n",
	\$small,
	'b',
);
write_exact_text(
	'icon.svg',
	'<svg xmlns="http://www.w3.org/2000/svg"><text>' . \$repo . '</text>',
	\$large,
	's',
);
write_exact_text(
	'tiny.svg',
	'<svg xmlns="http://www.w3.org/2000/svg">',
	\$small,
	'v',
);
write_binary(
	'diagram.png',
	\$png_signature . ( 'P' x $png_payload_fill_bytes ),
);

make_path('.git');
write_exact_text(
	'.git/internal-large.html',
	"<!doctype html>\\n<title>git internal html</title>\\n",
	\$large,
	'g',
);
FAKE_STAGIT

	$harness->write_file(
		path => $fake->{fake_stagit_path},
		content => $script,
	);
	chmod $EXECUTABLE_MODE, $fake->{fake_stagit_path}
		or die "Could not chmod 0700 $fake->{fake_stagit_path}: $OS_ERROR\n";

	return $fake;
}

sub assert_hook_success {
	my ($context) = @_;

	my $result = $context->{result};
	my $harness = $context->{harness};
	my $run_diag = $context->{run_diag};

	is_with_diag( $result->{command}->[0],
		$harness->hook_path, 'hook ran via executable child path',
		$run_diag );
	is_with_diag( $result->{status}, 0, 'hook child status is 0', $run_diag );
	is_with_diag( $result->{exit_code}, 0, 'hook exit code is 0', $run_diag );
	is_with_diag( $result->{signal}, 0,
		'hook terminated without signal', $run_diag );

	return;
}

sub assert_workspace_isolation {
	my ($context) = @_;

	my $harness = $context->{harness};
	my $repo = $context->{repo};
	my $production_webroot = $context->{production_webroot};
	my $real_helper_bin = $context->{real_helper_bin};
	my $expected_bindir = $context->{expected_bindir};
	my $stagit_dir = $context->{stagit_dir};
	my $run_diag = $context->{run_diag};

	for my $fixture_check (
		[ $harness->workspace_dir, 'workspace directory' ],
		[ $harness->home_dir, 'isolated HOME directory' ],
		[ $harness->webroot_dir, 'temp webroot directory' ],
		[ $harness->fake_command_dir, 'fake command directory' ],
		[ $repo->{bare_repo_dir}, 'bare repository fixture' ],
		[ $repo->{work_clone_dir}, 'work clone fixture' ],
		)
	{
		my ( $path, $label ) = @{$fixture_check};
		like_with_diag(
			$path,
			qr/^\Q@{[ $harness->workspace_dir ]}\E(?:\/|\z)/,
			"$label stays under the temp workspace", $run_diag,
		);
		unlike_with_diag(
			$path,
			qr/^\Q$production_webroot\E(?:\/|\z)/,
			"$label does not use the production webroot", $run_diag,
		);
	}

	isnt(
		$harness->home_dir,
		( $ENV{HOME} // q{} ),
		'isolated HOME differs from the caller HOME'
	);
	unlike_with_diag(
		$expected_bindir,
		qr/^\Q$real_helper_bin\E(?:\/|\z)/,
		'isolated helper bin does not point into the caller home helper-bin path',
		$run_diag,
	);

	like_with_diag(
		$stagit_dir,
		qr/^\Q@{[ $harness->webroot_dir ]}\E(?:\/|\z)/,
		'stagit output stays under the temp webroot', $run_diag,
	);
	unlike_with_diag(
		$stagit_dir,
		qr/^\Q$production_webroot\E(?:\/|\z)/,
		'stagit output does not use the production webroot', $run_diag,
	);

	return;
}

sub assert_stagit_output_basics {
	my ($context) = @_;

	my $run_diag = $context->{run_diag};

	ok_with_diag( !-e $context->{stale_path},
		'hook removed stale stagit output before recreating it',
		$run_diag );
	ok_with_diag( -d $context->{stagit_dir},
		'shared stagit output directory exists', $run_diag );
	ok_with_diag( -d $context->{stagit_git_dir},
		'hook cloned the bare repository into .git', $run_diag );
	ok_with_diag( -f $context->{head_path},
		'cloned bare repository preserved .git/HEAD', $run_diag );
	ok_with_diag( -f $context->{info_refs_path},
		'git update-server-info populated .git/info/refs', $run_diag );
	ok_with_diag( -f $context->{trace_path},
		'fake stagit trace was recorded', $run_diag );
	ok_with_diag( -f $context->{css_path},
		'hook copied shared style.css into stagit output', $run_diag );
	ok_with_diag( -f $context->{logo_path},
		'hook copied shared logo.png into stagit output', $run_diag );
	ok_with_diag( -f $context->{favicon_path},
		'hook copied shared favicon.png into stagit output', $run_diag );

	return;
}

sub assert_large_gzip_outputs {
	my ( $run_diag, $entries ) = @_;

	for my $entry ( @{$entries} ) {
		my ( $path, $gz_path, $label ) = @{$entry};
		ok_with_diag( -f $path, "$label exists", $run_diag );
		ok_with_diag( ( -e $path ? -s $path : 0 ) > $GZIP_THRESHOLD_BYTES,
			"$label exceeds the gzip threshold", $run_diag );
		ok_with_diag( -f $gz_path, "$label was gzipped", $run_diag );
	}

	return;
}

sub assert_small_gzip_outputs {
	my ( $run_diag, $entries ) = @_;

	for my $entry ( @{$entries} ) {
		my ( $path, $gz_path, $label ) = @{$entry};
		ok_with_diag( -f $path, "$label exists", $run_diag );
		ok_with_diag(
			( -e $path ? -s $path : $GZIP_THRESHOLD_BYTES + 1 ) <=
				$GZIP_THRESHOLD_BYTES,
			"$label stays at or below the gzip threshold",
			$run_diag
		);
		ok_with_diag( !-e $gz_path,
			"$label was not gzipped at or below the threshold", $run_diag );
	}

	return;
}

sub assert_png_and_git_gzip_exclusions {
	my ($context) = @_;

	my $run_diag = $context->{run_diag};

	ok_with_diag( -f $context->{diagram_png_path},
		'diagram.png exists', $run_diag );
	ok_with_diag(
		(
			-e $context->{diagram_png_path}
			? -s $context->{diagram_png_path}
			: 0
		) > $GZIP_THRESHOLD_BYTES,
		'diagram.png exceeds the gzip threshold',
		$run_diag
	);
	ok_with_diag( !-e $context->{diagram_png_gz_path},
		'diagram.png was not gzipped because png is ineligible',
		$run_diag );
	ok_with_diag( !-e $context->{logo_gz_path},
		'logo.png was not gzipped because png is ineligible', $run_diag );
	ok_with_diag( !-e $context->{favicon_gz_path},
		'favicon.png was not gzipped because png is ineligible',
		$run_diag );

	ok_with_diag( -f $context->{internal_git_html_path},
		'.git/internal-large.html exists', $run_diag );
	ok_with_diag(
		(
			-e $context->{internal_git_html_path}
			? -s $context->{internal_git_html_path}
			: 0
		) > $GZIP_THRESHOLD_BYTES,
		'.git/internal-large.html exceeds the gzip threshold',
		$run_diag,
	);
	ok_with_diag(
		!-e $context->{internal_git_html_gz_path},
		'.git/internal-large.html was not gzipped because .git paths are excluded',
		$run_diag
	);

	return;
}

sub assert_log_and_index_sync {
	my ($context) = @_;

	my $harness = $context->{harness};
	my $repo = $context->{repo};
	my $run_diag = $context->{run_diag};

SKIP: {
		if ( !-f $context->{log_path} || !-f $context->{index_path} ) {
			skip 'log.html or index.html missing', $HTML_SYNC_SKIP_COUNT;
		}
		my $log_html = $harness->read_file( $context->{log_path} );
		my $index_html = $harness->read_file( $context->{index_path} );
		is_with_diag( $index_html, $log_html,
			'index.html matches the generated log.html', $run_diag );
		like_with_diag(
			$log_html,
			qr/\Q$repo->{bare_repo_dir}\E/,
			'fake stagit log.html records the bare repo path', $run_diag
		);
		ok_with_diag(
			-f $context->{log_gz_path} && -f $context->{index_gz_path},
			'both log.html and index.html have matching gzip sidecars',
			$run_diag
		);
	}

	return;
}

sub assert_copied_assets {
	my ($context) = @_;

	my $harness = $context->{harness};
	my $assets = $context->{assets};
	my $run_diag = $context->{run_diag};

SKIP: {
		if ( !-f $context->{css_path}
			|| !-f $context->{logo_path}
			|| !-f $context->{favicon_path} )
		{
			skip 'copied assets missing', $COPIED_ASSETS_SKIP_COUNT;
		}
		is_with_diag(
			$harness->read_file( $context->{css_path} ),
			$harness->read_file( $assets->{style_css_path} ),
			'style.css was copied byte-for-byte from the seeded shared asset',
			$run_diag,
		);
		is_with_diag(
			$harness->read_file( $context->{logo_path} ),
			$harness->read_file( $assets->{logo_png_path} ),
			'logo.png was copied byte-for-byte from the seeded shared asset',
			$run_diag,
		);
		is_with_diag(
			$harness->read_file( $context->{favicon_path} ),
			$harness->read_file( $assets->{favicon_png_path} ),
			'favicon.png was copied byte-for-byte from the seeded shared asset',
			$run_diag,
		);
	}

	return;
}

sub assert_fake_stagit_trace {
	my ($context) = @_;

	my $harness = $context->{harness};
	my $repo = $context->{repo};
	my $run_diag = $context->{run_diag};

SKIP: {
		if ( !-f $context->{trace_path} ) {
			skip 'fake stagit trace missing', $STAGIT_TRACE_SKIP_COUNT;
		}
		my $trace = $harness->parse_trace_file( $context->{trace_path} );
		is_with_diag(
			$trace->{cwd},
			$context->{stagit_dir},
			'fake stagit recorded the stagit output directory as cwd',
			$run_diag
		);
		is_deeply(
			$trace->{argv},
			[ q{--}, $repo->{bare_repo_dir} ],
			'fake stagit recorded the expected argv'
		) or diag($run_diag);
	}

	return;
}

sub assert_verbose_output {
	my ($context) = @_;

	my $result = $context->{result};
	my $harness = $context->{harness};
	my $run_diag = $context->{run_diag};
	my $expected_bindir = $context->{expected_bindir};
	my $stagit_dir = $context->{stagit_dir};
	my $production_webroot = $context->{production_webroot};
	my $real_helper_bin = $context->{real_helper_bin};

	like_with_diag(
		$result->{stdout},
		qr/\QWEB SERVER DIRECTORY: @{[ $harness->webroot_dir ]}\E/,
		'verbose output names the temp webroot as the active web server directory',
		$run_diag,
	);
	like_with_diag(
		$result->{stdout},
		qr/\QBINARY DIRECTORY: $expected_bindir\E/,
		'verbose output uses the isolated HOME helper-bin path', $run_diag,
	);
	like_with_diag(
		$result->{stdout},
		qr/\QSTAGIT DIRECTORY: $stagit_dir\E/,
		'verbose output names the shared stagit output directory under the temp webroot',
		$run_diag,
	);
	unlike_with_diag(
		$result->{stdout},
		qr/\QWEB SERVER DIRECTORY: $production_webroot\E/,
		'verbose output does not report the production webroot as active',
		$run_diag,
	);
	unlike_with_diag(
		$result->{stdout},
		qr/\QBINARY DIRECTORY: $real_helper_bin\E/,
		'verbose output does not report the caller real helper-bin path',
		$run_diag,
	);

	return;
}

sub test_fake_stagit_shared_publishing_gzip_matrix {
	subtest 'fake stagit shared publishing gzip matrix' => sub {
		my $harness = PostReceive::TestHarness->new;
		my $style_css =
			"/* fake stagit shared publishing fixture */\n"
			. ( ".shared-fixture { color: #123456; background: #abcdef; }\n" x
				$STYLE_CSS_RULE_REPEAT_COUNT );
		my $logo_png = png_fixture_bytes("fake-logo-fixture\n");
		my $favicon_png = png_fixture_bytes("fake-favicon-fixture\n");
		my $prereq_diag = join "\n",
			'Install the missing prerequisite on PATH before running this shared publishing test.',
			'The test expects real git plus a fake stagit shim that is prepended on PATH.',
			$harness->workspace_diag,
			;

		cmp_ok( length $style_css,
			'>', $GZIP_THRESHOLD_BYTES,
			'seeded style.css exceeds the gzip threshold' );

		my $assets = setup_or_return(
			'seed shared stagit assets',
			sub {
				$harness->seed_stagit_assets(
					style_css => $style_css,
					logo_png => $logo_png,
					favicon_png => $favicon_png,
				);
			},
			$harness,
		);
		if ( !$assets ) {
			return;
		}

		my $fake = setup_or_return( 'install fake stagit gzip matrix',
			sub { install_fake_stagit_matrix($harness) }, $harness, );
		if ( !$fake ) {
			return;
		}

		like_with_diag(
			$harness->path,
			qr/^\Q@{[ $harness->fake_command_dir ]}\E(?::|\z)/,
			'fake command directory is prepended to PATH',
			$prereq_diag,
		);

		is_with_diag(
			$harness->executable_on_path('stagit'),
			$fake->{fake_stagit_path},
			'fake stagit resolves first on the harness PATH',
			$prereq_diag,
		);

		my $real_git = $harness->executable_on_path('git');
		ok_with_diag( defined $real_git,
			'real git executable available on harness PATH', $prereq_diag );
		if ( !defined $real_git ) {
			return;
		}

		unlike_with_diag(
			$real_git,
			qr/^\Q@{[ $harness->fake_command_dir ]}\E(?:\/|\z)/,
			'real git resolves outside the fake command directory',
			$prereq_diag,
		);

		my $repo = setup_or_return(
			'create learning_perl_exercises bare repository fixture',
			sub {
				$harness->create_bare_repo(
					repo_name => 'learning_perl_exercises.git',
					file_rel => 'README.md',
					file_content => "Learning Perl exercises fixture\n",
				);
			},
			$harness,
		);
		if ( !$repo ) {
			return;
		}

		my $production_webroot =
			catdir( rootdir(), qw(var www htdocs www.anthes.is) );
		my $real_helper_bin =
			catdir( ( $ENV{HOME} // q{} ), qw(.local bin) );
		my $expected_bindir = catdir( $harness->home_dir, qw(.local bin) );
		my $stagit_dir =
			catdir( $harness->webroot_dir, qw(src learning_perl_exercises) );
		my $stale_path = setup_or_return(
			'seed stale stagit output marker',
			sub {
				$harness->ensure_dir($stagit_dir);
				return $harness->write_file(
					path => catfile( $stagit_dir, 'stale-before-run.txt' ),
					content => "stale output that should be removed\n",
				);
			},
			$harness,
		);
		if ( !$stale_path ) {
			return;
		}

		my $result = $harness->run_post_receive( argv => ['-v'] );
		my $run_diag = $harness->describe_run($result);

		my $stagit_git_dir = catdir( $stagit_dir, '.git' );
		my $head_path = catfile( $stagit_git_dir, 'HEAD' );
		my $info_refs_path = catfile( $stagit_git_dir, qw(info refs) );
		my $trace_path = $harness->fake_stagit_trace_path;
		my $log_path = catfile( $stagit_dir, 'log.html' );
		my $log_gz_path = catfile( $stagit_dir, 'log.html.gz' );
		my $index_path = catfile( $stagit_dir, 'index.html' );
		my $index_gz_path = catfile( $stagit_dir, 'index.html.gz' );
		my $css_path = catfile( $stagit_dir, 'style.css' );
		my $css_gz_path = catfile( $stagit_dir, 'style.css.gz' );
		my $logo_path = catfile( $stagit_dir, 'logo.png' );
		my $logo_gz_path = catfile( $stagit_dir, 'logo.png.gz' );
		my $favicon_path = catfile( $stagit_dir, 'favicon.png' );
		my $favicon_gz_path = catfile( $stagit_dir, 'favicon.png.gz' );
		my $small_html_path = catfile( $stagit_dir, 'page-small.html' );
		my $small_html_gz_path =
			catfile( $stagit_dir, 'page-small.html.gz' );
		my $small_css_path = catfile( $stagit_dir, 'tiny.css' );
		my $small_css_gz_path = catfile( $stagit_dir, 'tiny.css.gz' );
		my $large_txt_path = catfile( $stagit_dir, 'notes.txt' );
		my $large_txt_gz_path = catfile( $stagit_dir, 'notes.txt.gz' );
		my $small_txt_path = catfile( $stagit_dir, 'tiny.txt' );
		my $small_txt_gz_path = catfile( $stagit_dir, 'tiny.txt.gz' );
		my $large_xml_path = catfile( $stagit_dir, 'feed.xml' );
		my $large_xml_gz_path = catfile( $stagit_dir, 'feed.xml.gz' );
		my $small_xml_path = catfile( $stagit_dir, 'tiny.xml' );
		my $small_xml_gz_path = catfile( $stagit_dir, 'tiny.xml.gz' );
		my $large_asc_path = catfile( $stagit_dir, 'release.asc' );
		my $large_asc_gz_path = catfile( $stagit_dir, 'release.asc.gz' );
		my $small_asc_path = catfile( $stagit_dir, 'tiny.asc' );
		my $small_asc_gz_path = catfile( $stagit_dir, 'tiny.asc.gz' );
		my $large_svg_path = catfile( $stagit_dir, 'icon.svg' );
		my $large_svg_gz_path = catfile( $stagit_dir, 'icon.svg.gz' );
		my $small_svg_path = catfile( $stagit_dir, 'tiny.svg' );
		my $small_svg_gz_path = catfile( $stagit_dir, 'tiny.svg.gz' );
		my $diagram_png_path = catfile( $stagit_dir, 'diagram.png' );
		my $diagram_png_gz_path = catfile( $stagit_dir, 'diagram.png.gz' );
		my $internal_git_html_path =
			catfile( $stagit_git_dir, 'internal-large.html' );
		my $internal_git_html_gz_path =
			catfile( $stagit_git_dir, 'internal-large.html.gz' );

		my %assert_context = (
			assets => $assets,
			css_path => $css_path,
			diagram_png_gz_path => $diagram_png_gz_path,
			diagram_png_path => $diagram_png_path,
			expected_bindir => $expected_bindir,
			favicon_gz_path => $favicon_gz_path,
			favicon_path => $favicon_path,
			harness => $harness,
			head_path => $head_path,
			index_gz_path => $index_gz_path,
			index_path => $index_path,
			info_refs_path => $info_refs_path,
			internal_git_html_gz_path => $internal_git_html_gz_path,
			internal_git_html_path => $internal_git_html_path,
			log_gz_path => $log_gz_path,
			log_path => $log_path,
			logo_gz_path => $logo_gz_path,
			logo_path => $logo_path,
			production_webroot => $production_webroot,
			real_helper_bin => $real_helper_bin,
			repo => $repo,
			result => $result,
			run_diag => $run_diag,
			stagit_dir => $stagit_dir,
			stagit_git_dir => $stagit_git_dir,
			stale_path => $stale_path,
			trace_path => $trace_path,
		);

		assert_hook_success( \%assert_context );
		assert_workspace_isolation( \%assert_context );
		assert_stagit_output_basics( \%assert_context );
		assert_large_gzip_outputs(
			$run_diag,
			[
				[ $log_path, $log_gz_path, 'log.html' ],
				[ $index_path, $index_gz_path, 'index.html' ],
				[ $css_path, $css_gz_path, 'style.css' ],
				[ $large_txt_path, $large_txt_gz_path, 'notes.txt' ],
				[ $large_xml_path, $large_xml_gz_path, 'feed.xml' ],
				[ $large_asc_path, $large_asc_gz_path, 'release.asc' ],
				[ $large_svg_path, $large_svg_gz_path, 'icon.svg' ],
			],
		);
		assert_small_gzip_outputs(
			$run_diag,
			[
				[
					$small_html_path, $small_html_gz_path,
					'page-small.html'
				],
				[ $small_css_path, $small_css_gz_path, 'tiny.css' ],
				[ $small_txt_path, $small_txt_gz_path, 'tiny.txt' ],
				[ $small_xml_path, $small_xml_gz_path, 'tiny.xml' ],
				[ $small_asc_path, $small_asc_gz_path, 'tiny.asc' ],
				[ $small_svg_path, $small_svg_gz_path, 'tiny.svg' ],
			],
		);
		assert_png_and_git_gzip_exclusions( \%assert_context );
		assert_log_and_index_sync( \%assert_context );
		assert_copied_assets( \%assert_context );
		assert_fake_stagit_trace( \%assert_context );
		assert_verbose_output( \%assert_context );

		done_testing();
	};

	return;
}

sub test_missing_shared_stagit_asset_fails_loudly {
	subtest 'missing shared stagit asset fails loudly' => sub {
		my $harness = PostReceive::TestHarness->new;
		my $prereq_diag = join "\n",
			'Install the missing prerequisite on PATH before running this shared publishing test.',
			'The test expects real git plus a fake stagit shim that is prepended on PATH.',
			$harness->workspace_diag;

		my $assets =
			setup_or_return(
				'seed shared stagit assets for missing-asset failure',
				sub { $harness->seed_stagit_assets(); }, $harness, );
		if ( !$assets ) {
			return;
		}

		my $fake =
			setup_or_return( 'install fake stagit for missing-asset failure',
				sub { $harness->install_fake_stagit }, $harness, );
		if ( !$fake ) {
			return;
		}

		is_with_diag(
			$harness->executable_on_path('stagit'),
			$fake->{fake_stagit_path},
			'fake stagit resolves first on the harness PATH',
			$prereq_diag,
		);

		my $real_git = $harness->executable_on_path('git');
		ok_with_diag( defined $real_git,
			'real git executable available on harness PATH', $prereq_diag );
		if ( !defined $real_git ) {
			return;
		}

		unlike_with_diag(
			$real_git,
			qr/^\Q@{[ $harness->fake_command_dir ]}\E(?:\/|\z)/,
			'real git resolves outside the fake command directory',
			$prereq_diag,
		);

		my $repo = setup_or_return(
			'create generic bare repository fixture',
			sub {
				$harness->create_bare_repo(
					repo_name => 'generic_project.git',
					file_rel => 'README.md',
					file_content =>
						"Generic shared asset failure fixture\n",
				);
			},
			$harness,
		);
		if ( !$repo ) {
			return;
		}

		my $removed = setup_or_return(
			'remove shared style.css before hook run',
			sub {
				unlink $assets->{style_css_path}
					or die
					"Could not remove $assets->{style_css_path}: $OS_ERROR\n";
				return 1;
			},
			$harness,
		);
		if ( !$removed ) {
			return;
		}

		my $result = $harness->run_post_receive( argv => ['-v'] );
		my $run_diag = $harness->describe_run($result);

		my $stagit_dir =
			catdir( $harness->webroot_dir, qw(src generic_project) );
		my $trace_path = $harness->fake_stagit_trace_path;
		my $index_path = catfile( $stagit_dir, 'index.html' );
		my $style_destination = catfile( $stagit_dir, 'style.css' );

		ok_with_diag(
			$result->{status} != 0,
			'hook child status is non-zero when shared style.css is missing',
			$run_diag
		);
		ok_with_diag( $result->{exit_code} != 0,
			'hook exit code is non-zero when shared style.css is missing',
			$run_diag );
		is_with_diag( $result->{signal}, 0,
			'hook failure is an exit, not a signal', $run_diag );
		ok_with_diag( -f $trace_path,
			'fake stagit completed before the copy failure', $run_diag );
		ok_with_diag(
			-f $index_path,
			'log.html was copied to index.html before the shared asset failure',
			$run_diag
		);
		ok_with_diag( !-e $style_destination,
			'missing shared style.css was not silently published',
			$run_diag );
		like_with_diag(
			$result->{stderr},
			qr/copying shared stagit asset CSS failed/i,
			'stderr identifies the failed shared asset copy',
			$run_diag,
		);
		like_with_diag(
			$result->{stderr},
			qr/\Q$assets->{style_css_path}\E/,
			'stderr names the missing shared asset source', $run_diag,
		);
		like_with_diag( $result->{stderr}, qr/\Q$style_destination\E/,
			'stderr names the intended shared asset destination',
			$run_diag, );

		done_testing();
	};

	return;
}

test_fake_stagit_shared_publishing_gzip_matrix();
test_missing_shared_stagit_asset_fails_loudly();
done_testing();
