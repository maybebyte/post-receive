#!/usr/bin/env perl
use strict;
use warnings;

use File::Basename qw(dirname);
use File::Path qw(make_path);
use File::Spec;
use File::Spec::Functions qw(catdir catfile rootdir);
use Test::More;
use lib File::Spec->catdir( dirname( File::Spec->rel2abs(__FILE__) ), 'lib' );

use PostReceive::TestHarness;

sub harness_diag {
	my ($harness) = @_;

	return join(
		"\n",
		'workspace_dir: ' . $harness->workspace_dir,
		'home_dir: ' . $harness->home_dir,
		'webroot_dir: ' . $harness->webroot_dir,
		'fake_command_dir: ' . $harness->fake_command_dir,
		'repo_fixture_root: ' . $harness->repo_fixture_root,
		'PATH: ' . $harness->path,
	);
}

sub setup_or_return {
	my ( $label, $code, $harness ) = @_;

	my $value = eval { $code->() };
	if ( !$@ ) {
		pass($label);
		return $value;
	}

	fail($label);
	diag($@);
	diag( harness_diag($harness) );
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

sub executable_on_path {
	my ( $path, $name ) = @_;

	for my $dir ( split /:/, $path // q{} ) {
		next unless defined $dir && length $dir;
		my $candidate = File::Spec->catfile( $dir, $name );
		return $candidate if -f $candidate && -x $candidate;
	}

	return;
}

sub parse_fake_stagit_trace {
	my ($trace_text) = @_;

	my %trace = ( argv => [] );
	for my $line ( split /\n/, $trace_text ) {
		if ( $line =~ /^cwd=(.*)\z/ ) {
			$trace{cwd} = $1;
			next;
		}
		if ( $line =~ /^argv\[(\d+)\]=(.*)\z/ ) {
			$trace{argv}->[$1] = $2;
		}
	}

	return \%trace;
}

sub perl_single_quote {
	my ($text) = @_;

	$text =~ s{\\}{\\\\}g;
	$text =~ s{'}{\\'}g;

	return "'$text'";
}

sub write_file {
	my (%args) = @_;

	my $path = $args{path} // die "write_file requires a path\n";
	my $content = defined $args{content} ? $args{content} : q{};

	open my $fh, '>', $path
		or die "Could not open $path for writing: $!\n";
	if ( $args{binary} ) {
		binmode $fh or die "Could not enable binmode for $path: $!\n";
	}
	print {$fh} $content
		or die "Could not write to $path: $!\n";
	close $fh
		or die "Could not close $path: $!\n";

	return $path;
}

sub install_fake_stagit_matrix {
	my ($harness) = @_;

	my $fake = $harness->install_fake_stagit;
	my $trace_literal = perl_single_quote( $fake->{trace_path} );

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
my \$large = 1501;
my \$small = 1400;

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
	"\\x89PNG\\x0D\\x0A\\x1A\\x0A" . ( 'P' x 1700 ),
);

make_path('.git');
write_exact_text(
	'.git/internal-large.html',
	"<!doctype html>\\n<title>git internal html</title>\\n",
	\$large,
	'g',
);
FAKE_STAGIT

	write_file(
		path    => $fake->{fake_stagit_path},
		content => $script,
	);
	chmod 0700, $fake->{fake_stagit_path}
		or die "Could not chmod 0700 $fake->{fake_stagit_path}: $!\n";

	return $fake;
}

subtest 'fake stagit shared publishing gzip matrix' => sub {
	my $harness = PostReceive::TestHarness->new;
	my $style_css = "/* fake stagit shared publishing fixture */\n"
		. ( ".shared-fixture { color: #123456; background: #abcdef; }\n" x 32 );
	my $logo_png = "\x89PNG\x0D\x0A\x1A\x0Afake-logo-fixture\n";
	my $favicon_png = "\x89PNG\x0D\x0A\x1A\x0Afake-favicon-fixture\n";
	my $prereq_diag = join(
		"\n",
		'Install the missing prerequisite on PATH before running this shared publishing test.',
		'The test expects real git plus a fake stagit shim that is prepended on PATH.',
		harness_diag($harness),
	);

	cmp_ok( length($style_css), '>', 1400, 'seeded style.css exceeds the gzip threshold' );

	my $assets = setup_or_return(
		'seed shared stagit assets',
		sub {
			$harness->seed_stagit_assets(
				style_css   => $style_css,
				logo_png    => $logo_png,
				favicon_png => $favicon_png,
			);
		},
		$harness,
	);
	return unless $assets;

	my $fake = setup_or_return(
		'install fake stagit gzip matrix',
		sub { install_fake_stagit_matrix($harness) },
		$harness,
	);
	return unless $fake;

	like_with_diag(
		$harness->path,
		qr/^\Q@{[ $harness->fake_command_dir ]}\E(?::|\z)/,
		'fake command directory is prepended to PATH',
		$prereq_diag,
	);

	is_with_diag(
		executable_on_path( $harness->path, 'stagit' ),
		$fake->{fake_stagit_path},
		'fake stagit resolves first on the harness PATH',
		$prereq_diag,
	);

	my $real_git = executable_on_path( $harness->path, 'git' );
	ok_with_diag( defined $real_git, 'real git executable available on harness PATH', $prereq_diag );
	return unless defined $real_git;

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
				repo_name    => 'learning_perl_exercises.git',
				file_rel     => 'README.md',
				file_content => "Learning Perl exercises fixture\n",
			);
		},
		$harness,
	);
	return unless $repo;

	my $production_webroot = catdir( rootdir(), qw(var www htdocs www.anthes.is) );
	my $real_helper_bin = catdir( ( $ENV{HOME} // q{} ), qw(.local bin) );
	my $expected_bindir = catdir( $harness->home_dir, qw(.local bin) );
	my $stagit_dir = catdir( $harness->webroot_dir, qw(src learning_perl_exercises) );
	my $stale_path = setup_or_return(
		'seed stale stagit output marker',
		sub {
			make_path($stagit_dir);
			my $path = catfile( $stagit_dir, 'stale-before-run.txt' );
			open my $fh, '>', $path;
			print {$fh} "stale output that should be removed\n";
			close $fh;
			return $path;
		},
		$harness,
	);
	return unless $stale_path;

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
	my $small_html_gz_path = catfile( $stagit_dir, 'page-small.html.gz' );
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
	my $internal_git_html_path = catfile( $stagit_git_dir, 'internal-large.html' );
	my $internal_git_html_gz_path = catfile( $stagit_git_dir, 'internal-large.html.gz' );

	is_with_diag( $result->{command}->[0], $harness->hook_path, 'hook ran via executable child path', $run_diag );
	is_with_diag( $result->{status}, 0, 'hook child status is 0', $run_diag );
	is_with_diag( $result->{exit_code}, 0, 'hook exit code is 0', $run_diag );
	is_with_diag( $result->{signal}, 0, 'hook terminated without signal', $run_diag );

	for my $fixture_check (
		[ $harness->workspace_dir, 'workspace directory' ],
		[ $harness->home_dir, 'isolated HOME directory' ],
		[ $harness->webroot_dir, 'temp webroot directory' ],
		[ $harness->fake_command_dir, 'fake command directory' ],
		[ $repo->{bare_repo_dir}, 'bare repository fixture' ],
		[ $repo->{work_clone_dir}, 'work clone fixture' ],
	) {
		my ( $path, $label ) = @{$fixture_check};
		like_with_diag(
			$path,
			qr/^\Q@{[ $harness->workspace_dir ]}\E(?:\/|\z)/,
			"$label stays under the temp workspace",
			$run_diag,
		);
		unlike_with_diag(
			$path,
			qr/^\Q$production_webroot\E(?:\/|\z)/,
			"$label does not use the production webroot",
			$run_diag,
		);
	}

	isnt( $harness->home_dir, ( $ENV{HOME} // q{} ), 'isolated HOME differs from the caller HOME' );
	unlike_with_diag(
		$expected_bindir,
		qr/^\Q$real_helper_bin\E(?:\/|\z)/,
		'isolated helper bin does not point into the caller home helper-bin path',
		$run_diag,
	);

	like_with_diag(
		$stagit_dir,
		qr/^\Q@{[ $harness->webroot_dir ]}\E(?:\/|\z)/,
		'stagit output stays under the temp webroot',
		$run_diag,
	);
	unlike_with_diag(
		$stagit_dir,
		qr/^\Q$production_webroot\E(?:\/|\z)/,
		'stagit output does not use the production webroot',
		$run_diag,
	);

	ok_with_diag( !-e $stale_path, 'hook removed stale stagit output before recreating it', $run_diag );
	ok_with_diag( -d $stagit_dir, 'shared stagit output directory exists', $run_diag );
	ok_with_diag( -d $stagit_git_dir, 'hook cloned the bare repository into .git', $run_diag );
	ok_with_diag( -f $head_path, 'cloned bare repository preserved .git/HEAD', $run_diag );
	ok_with_diag( -f $info_refs_path, 'git update-server-info populated .git/info/refs', $run_diag );
	ok_with_diag( -f $trace_path, 'fake stagit trace was recorded', $run_diag );
	ok_with_diag( -f $css_path, 'hook copied shared style.css into stagit output', $run_diag );
	ok_with_diag( -f $logo_path, 'hook copied shared logo.png into stagit output', $run_diag );
	ok_with_diag( -f $favicon_path, 'hook copied shared favicon.png into stagit output', $run_diag );

	for my $entry (
		[ $log_path,       $log_gz_path,       'log.html' ],
		[ $index_path,     $index_gz_path,     'index.html' ],
		[ $css_path,       $css_gz_path,       'style.css' ],
		[ $large_txt_path, $large_txt_gz_path, 'notes.txt' ],
		[ $large_xml_path, $large_xml_gz_path, 'feed.xml' ],
		[ $large_asc_path, $large_asc_gz_path, 'release.asc' ],
		[ $large_svg_path, $large_svg_gz_path, 'icon.svg' ],
	) {
		my ( $path, $gz_path, $label ) = @{$entry};
		ok_with_diag( -f $path, "$label exists", $run_diag );
		ok_with_diag( ( -e $path ? -s $path : 0 ) > 1400, "$label exceeds the gzip threshold", $run_diag );
		ok_with_diag( -f $gz_path, "$label was gzipped", $run_diag );
	}

	for my $entry (
		[ $small_html_path, $small_html_gz_path, 'page-small.html' ],
		[ $small_css_path,  $small_css_gz_path,  'tiny.css' ],
		[ $small_txt_path,  $small_txt_gz_path,  'tiny.txt' ],
		[ $small_xml_path,  $small_xml_gz_path,  'tiny.xml' ],
		[ $small_asc_path,  $small_asc_gz_path,  'tiny.asc' ],
		[ $small_svg_path,  $small_svg_gz_path,  'tiny.svg' ],
	) {
		my ( $path, $gz_path, $label ) = @{$entry};
		ok_with_diag( -f $path, "$label exists", $run_diag );
		ok_with_diag( ( -e $path ? -s $path : 1401 ) <= 1400, "$label stays at or below the gzip threshold", $run_diag );
		ok_with_diag( !-e $gz_path, "$label was not gzipped at or below the threshold", $run_diag );
	}

	ok_with_diag( -f $diagram_png_path, 'diagram.png exists', $run_diag );
	ok_with_diag( ( -e $diagram_png_path ? -s $diagram_png_path : 0 ) > 1400, 'diagram.png exceeds the gzip threshold', $run_diag );
	ok_with_diag( !-e $diagram_png_gz_path, 'diagram.png was not gzipped because png is ineligible', $run_diag );
	ok_with_diag( !-e $logo_gz_path, 'logo.png was not gzipped because png is ineligible', $run_diag );
	ok_with_diag( !-e $favicon_gz_path, 'favicon.png was not gzipped because png is ineligible', $run_diag );

	ok_with_diag( -f $internal_git_html_path, '.git/internal-large.html exists', $run_diag );
	ok_with_diag(
		( -e $internal_git_html_path ? -s $internal_git_html_path : 0 ) > 1400,
		'.git/internal-large.html exceeds the gzip threshold',
		$run_diag,
	);
	ok_with_diag( !-e $internal_git_html_gz_path, '.git/internal-large.html was not gzipped because .git paths are excluded', $run_diag );

	SKIP: {
		skip 'log.html or index.html missing', 3 unless -f $log_path && -f $index_path;
		my $log_html = $harness->read_file($log_path);
		my $index_html = $harness->read_file($index_path);
		is_with_diag( $index_html, $log_html, 'index.html matches the generated log.html', $run_diag );
		like_with_diag( $log_html, qr/\Q$repo->{bare_repo_dir}\E/, 'fake stagit log.html records the bare repo path', $run_diag );
		ok_with_diag( -f $log_gz_path && -f $index_gz_path, 'both log.html and index.html have matching gzip sidecars', $run_diag );
	}

	SKIP: {
		skip 'copied assets missing', 3 unless -f $css_path && -f $logo_path && -f $favicon_path;
		is_with_diag(
			$harness->read_file($css_path),
			$harness->read_file( $assets->{style_css_path} ),
			'style.css was copied byte-for-byte from the seeded shared asset',
			$run_diag,
		);
		is_with_diag(
			$harness->read_file($logo_path),
			$harness->read_file( $assets->{logo_png_path} ),
			'logo.png was copied byte-for-byte from the seeded shared asset',
			$run_diag,
		);
		is_with_diag(
			$harness->read_file($favicon_path),
			$harness->read_file( $assets->{favicon_png_path} ),
			'favicon.png was copied byte-for-byte from the seeded shared asset',
			$run_diag,
		);
	}

	SKIP: {
		skip 'fake stagit trace missing', 2 unless -f $trace_path;
		my $trace = parse_fake_stagit_trace( $harness->read_file($trace_path) );
		is_with_diag( $trace->{cwd}, $stagit_dir, 'fake stagit recorded the stagit output directory as cwd', $run_diag );
		is_deeply( $trace->{argv}, [ '--', $repo->{bare_repo_dir} ], 'fake stagit recorded the expected argv' )
			or diag($run_diag);
	}

	like_with_diag(
		$result->{stdout},
		qr/\QWEB SERVER DIRECTORY: @{[ $harness->webroot_dir ]}\E/,
		'verbose output names the temp webroot as the active web server directory',
		$run_diag,
	);
	like_with_diag(
		$result->{stdout},
		qr/\QBINARY DIRECTORY: $expected_bindir\E/,
		'verbose output uses the isolated HOME helper-bin path',
		$run_diag,
	);
	like_with_diag(
		$result->{stdout},
		qr/\QSTAGIT DIRECTORY: $stagit_dir\E/,
		'verbose output names the shared stagit output directory under the temp webroot',
		$run_diag,
	);
	like_with_diag(
		$result->{stdout},
		qr/\QRunning 'git clone --bare -- $repo->{bare_repo_dir} $stagit_git_dir'\E/,
		'verbose output records the real bare clone into .git',
		$run_diag,
	);
	like_with_diag(
		$result->{stdout},
		qr/\QRunning 'git update-server-info' for learning_perl_exercises\E/,
		'verbose output records git update-server-info',
		$run_diag,
	);
	like_with_diag(
		$result->{stdout},
		qr/\QRunning 'stagit -- $repo->{bare_repo_dir}'\E/,
		'verbose output records the fake stagit invocation against the bare repository fixture',
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

	done_testing();
};

done_testing();
