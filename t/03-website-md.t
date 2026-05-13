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
Readonly::Scalar my $RSSG_PAYLOAD_BYTES => 1_700;
Readonly::Scalar my $SSG_LATE_FAILURE_EXIT_CODE => 42;
Readonly::Scalar my $RSSG_LATE_FAILURE_EXIT_CODE => 43;
Readonly::Scalar my $WEBSITE_HELPER_TRACE_SKIP_COUNT => 12;
Readonly::Scalar my $STAGIT_TRACE_SKIP_COUNT => 2;
Readonly::Scalar my $GENERATED_WEBSITE_SKIP_COUNT => 5;
Readonly::Scalar my $COPIED_SHARED_ASSETS_SKIP_COUNT => 3;
Readonly::Scalar my $LOG_INDEX_SYNC_SKIP_COUNT => 2;

sub setup_or_return {
	my ( $label, $code, $harness ) = @_;

	my $value = eval { $code->() };
	if ( !$EVAL_ERROR ) {
		pass($label);
		return $value;
	}

	fail($label);
	diag($EVAL_ERROR);
	diag( $harness->workspace_diag );
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

sub contains_with_diag {
	my ( $got, $needle, $label, $diag ) = @_;
	my $has_needle = index( $got, $needle ) >= 0;
	ok( $has_needle, $label ) or diag($diag);
	return $has_needle;
}

sub does_not_contain_with_diag {
	my ( $got, $needle, $label, $diag ) = @_;
	my $has_no_needle = index( $got, $needle ) < 0;
	ok( $has_no_needle, $label ) or diag($diag);
	return $has_no_needle;
}

sub perl_single_quote {
	my ($text) = @_;

	$text =~ s{\\}{\\\\}g;
	$text =~ s{'}{\\'}g;

	return "'$text'";
}

sub install_fake_website_helpers {
	my ( $harness, %args ) = @_;

	my $bindir =
		$harness->ensure_dir( catdir( $harness->home_dir, qw(.local bin) ) );

	my $ssg_path = catfile( $bindir, 'ssg6' );
	my $rssg_path = catfile( $bindir, 'rssg' );
	my $ssg_trace_path = catfile( $harness->workspace_dir, 'fake-ssg6.trace' );
	my $rssg_trace_path = catfile( $harness->workspace_dir, 'fake-rssg.trace' );
	my $ssg_trace_literal = perl_single_quote($ssg_trace_path);
	my $rssg_trace_literal = perl_single_quote($rssg_trace_path);

	my $ssg_late_failure = q{};
	if ( defined $args{ssg_exit_after_side_effects} ) {
		my $exit_code = $args{ssg_exit_after_side_effects};
		if ( $exit_code !~ /\A\d+\z/ ) {
			die "ssg_exit_after_side_effects must be an unsigned integer\n";
		}
		$ssg_late_failure = <<"SSG_LATE_FAILURE";
print STDERR "fake ssg6 wrote required side effects and is failing now\\n";
exit $exit_code;
SSG_LATE_FAILURE
	}

	my $rssg_finish = <<'RSSG_SUCCESS';
$xml .= qq{</description></item></channel></rss>\n};
print $xml
	or die "Could not write RSS XML to STDOUT: $!\n";
RSSG_SUCCESS

	if ( defined $args{rssg_exit_after_partial_output} ) {
		my $exit_code = $args{rssg_exit_after_partial_output};
		if ( $exit_code !~ /\A\d+\z/ ) {
			die "rssg_exit_after_partial_output must be an unsigned integer\n";
		}
		$rssg_finish = <<"RSSG_LATE_FAILURE";
print \$xml
	or die "Could not write partial RSS XML to STDOUT: \$!\\n";
print STDERR "fake rssg wrote partial RSS output and is failing now\\n";
exit $exit_code;
RSSG_LATE_FAILURE
	}

	my $ssg_script = <<'FAKE_SSG';
#!/usr/bin/env perl
use strict;
use warnings;
use Cwd qw(getcwd);
use File::Path qw(make_path);

sub write_text {
	my ( $path, $content ) = @_;
	open my $fh, '>', $path
		or die "Could not open $path for writing: $!\n";
	print {$fh} $content
		or die "Could not write to $path: $!\n";
	close $fh
		or die "Could not close $path: $!\n";
}

sub write_binary {
	my ( $path, $content ) = @_;
	open my $fh, '>', $path
		or die "Could not open $path for writing: $!\n";
	binmode $fh or die "Could not enable binmode for $path: $!\n";
	print {$fh} $content
		or die "Could not write to $path: $!\n";
	close $fh
		or die "Could not close $path: $!\n";
}

sub write_exact_text {
	my ( $path, $prefix, $size, $fill ) = @_;
	my $remaining = $size - length $prefix;
	die "Prefix for $path exceeds requested size of $size bytes\n"
		if $remaining < 0;
	write_text( $path, $prefix . ( $fill x $remaining ) );
}

my ( $clone_dir, $webroot, $website_name, $domain_with_schema ) = @ARGV;
my $trace_path = __TRACE_PATH__;

open my $trace_fh, '>', $trace_path
	or die "Could not open $trace_path for writing: $!\n";
print {$trace_fh} "helper=ssg6\n";
print {$trace_fh} "self=$0\n";
print {$trace_fh} "cwd=", getcwd(), "\n";
for my $index ( 0 .. $#ARGV ) {
	print {$trace_fh} "argv[$index]=", $ARGV[$index], "\n";
}
print {$trace_fh} "index_exists=", ( -f "$clone_dir/index.md" ? 1 : 0 ), "\n";

make_path( $webroot, "$webroot/src", "$webroot/stagit" );

write_exact_text(
	"$webroot/index.html",
	"<!doctype html>\n<title>$website_name</title>\n<p>$domain_with_schema</p>\n",
	__LARGE_FIXTURE_BYTES__,
	'I',
);
write_exact_text(
	"$webroot/about.txt",
	"About $website_name at $domain_with_schema\n",
	__LARGE_FIXTURE_BYTES__,
	'A',
);
write_text( "$webroot/.files", "generated by fake ssg6\n" );
print {$trace_fh} "created_dot_files=1\n";
write_exact_text(
	"$webroot/src/src.html",
	"<!doctype html>\n<title>src page</title>\n<p>$clone_dir</p>\n",
	__LARGE_FIXTURE_BYTES__,
	'S',
);
write_exact_text(
	"$webroot/src/other.html",
	"<!doctype html>\n<title>other page</title>\n<p>$clone_dir</p>\n",
	__LARGE_FIXTURE_BYTES__,
	'O',
);
write_exact_text(
	"$webroot/stagit/style.css",
	"/* fake ssg6 stagit asset for $website_name */\n",
	__LARGE_FIXTURE_BYTES__,
	'C',
);
write_binary( "$webroot/stagit/logo.png", "\x89PNG\x0D\x0A\x1A\x0Afake-website-logo\n" );
write_binary( "$webroot/stagit/favicon.png", "\x89PNG\x0D\x0A\x1A\x0Afake-website-favicon\n" );

close $trace_fh
	or die "Could not close $trace_path: $!\n";
__SSG_LATE_FAILURE__
FAKE_SSG
	$ssg_script =~ s/__TRACE_PATH__/$ssg_trace_literal/;
	$ssg_script =~ s/__LARGE_FIXTURE_BYTES__/$LARGE_FIXTURE_BYTES/g;
	$ssg_script =~ s/__SSG_LATE_FAILURE__/$ssg_late_failure/;

	my $rssg_script = <<'FAKE_RSSG';
#!/usr/bin/env perl
use strict;
use warnings;
use Cwd qw(getcwd);

my ( $index_path, $website_title ) = @ARGV;
my $trace_path = __TRACE_PATH__;

open my $trace_fh, '>', $trace_path
	or die "Could not open $trace_path for writing: $!\n";
print {$trace_fh} "helper=rssg\n";
print {$trace_fh} "self=$0\n";
print {$trace_fh} "cwd=", getcwd(), "\n";
for my $index ( 0 .. $#ARGV ) {
	print {$trace_fh} "argv[$index]=", $ARGV[$index], "\n";
}
print {$trace_fh} "index_exists=", ( -f $index_path ? 1 : 0 ), "\n";
close $trace_fh
	or die "Could not close $trace_path: $!\n";

my $xml = qq{<?xml version="1.0"?>\n<rss><channel><title>$website_title</title><item>$index_path</item><description>};
$xml .= 'R' x __RSSG_PAYLOAD_BYTES__;
__RSSG_FINISH__
FAKE_RSSG
	$rssg_script =~ s/__TRACE_PATH__/$rssg_trace_literal/;
	$rssg_script =~ s/__RSSG_PAYLOAD_BYTES__/$RSSG_PAYLOAD_BYTES/;
	$rssg_script =~ s/__RSSG_FINISH__/$rssg_finish/;

	$harness->write_file(
		path => $ssg_path,
		content => $ssg_script,
	);
	$harness->write_file(
		path => $rssg_path,
		content => $rssg_script,
	);
	chmod $EXECUTABLE_MODE, $ssg_path
		or die "Could not chmod 0700 $ssg_path: $OS_ERROR\n";
	chmod $EXECUTABLE_MODE, $rssg_path
		or die "Could not chmod 0700 $rssg_path: $OS_ERROR\n";

	return {
		bindir => $bindir,
		ssg_path => $ssg_path,
		rssg_path => $rssg_path,
		ssg_trace_path => $ssg_trace_path,
		rssg_trace_path => $rssg_trace_path,
	};
}

sub run_diag_with_helper_traces {
	my ( $harness, $result, $helpers ) = @_;

	my @lines = ( $harness->describe_run($result) );
	for my $entry (
		[ 'fake_ssg6_path', $helpers->{ssg_path}, 0 ],
		[ 'fake_ssg6_trace_path', $helpers->{ssg_trace_path}, 1 ],
		[ 'fake_rssg_path', $helpers->{rssg_path}, 0 ],
		[ 'fake_rssg_trace_path', $helpers->{rssg_trace_path}, 1 ],
		)
	{
		my ( $label, $path, $include_contents ) = @{$entry};
		push @lines, "$label: $path";
		if ( !$include_contents ) {
			next;
		}
		if ( -e $path ) {
			push @lines, "$label contents:", $harness->read_file($path);
		}
		else {
			push @lines, "$label contents:", '(missing)';
		}
	}

	return join "\n", @lines;
}

sub assert_website_hook_success {
	my ($context) = @_;

	my $harness = $context->{harness};
	my $result = $context->{result};
	my $run_diag = $context->{run_diag};

	is_with_diag( $result->{command}->[0],
		$harness->hook_path, 'hook ran via executable child path',
		$run_diag );
	is_with_diag( $result->{status}, 0, 'hook child status is 0', $run_diag );
	is_with_diag( $result->{exit_code}, 0, 'hook exit code is 0', $run_diag );
	is_with_diag( $result->{signal}, 0, 'hook terminated without signal',
		$run_diag );

	return;
}

sub assert_website_workspace_isolation {
	my ($context) = @_;

	my $harness = $context->{harness};
	my $helpers = $context->{helpers};
	my $repo = $context->{repo};
	my $run_diag = $context->{run_diag};

	for my $fixture_check (
		[ $harness->workspace_dir, 'workspace directory' ],
		[ $harness->home_dir, 'isolated HOME directory' ],
		[ $harness->webroot_dir, 'temp webroot directory' ],
		[ $helpers->{bindir}, 'isolated helper bin directory' ],
		[ $helpers->{ssg_path}, 'fake ssg6 executable' ],
		[ $helpers->{rssg_path}, 'fake rssg executable' ],
		[ $repo->{bare_repo_dir}, 'bare repository fixture' ],
		[ $repo->{work_clone_dir}, 'work clone fixture' ],
		[ $context->{stagit_dir}, 'shared stagit output directory' ],
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
			qr/^\Q$context->{production_webroot}\E(?:\/|\z)/,
			"$label does not use the production webroot", $run_diag,
		);
	}

	isnt $harness->home_dir, ( $ENV{HOME} // q{} ),
		'isolated HOME differs from the caller HOME';
	is_with_diag(
		$context->{expected_bindir},
		$helpers->{bindir},
		'expected isolated helper bindir matches the installed helper location',
		$run_diag
	);
	unlike_with_diag(
		$context->{expected_bindir},
		qr/^\Q$context->{real_helper_bin}\E(?:\/|\z)/,
		'isolated helper bin does not point into the caller home helper-bin path',
		$run_diag,
	);

	return;
}

sub assert_website_cleanup_preservation {
	my ($context) = @_;

	my $run_diag = $context->{run_diag};

	ok_with_diag( !-e $context->{stale_root_path},
		'hook removed stale root-level webroot file', $run_diag );
	ok_with_diag( !-e $context->{stale_root_nested_path},
		'hook removed stale nested root-level webroot file', $run_diag );
	ok_with_diag(
		!-e $context->{stale_root_stagit_path},
		'hook removed stale root-level stagit asset before the fake website helper recreated shared assets',
		$run_diag
	);
	ok_with_diag( -f $context->{preserved_src_path},
		'hook preserved existing src fixture outside src/website_md',
		$run_diag );
	ok_with_diag( -f $context->{preserved_other_repo_path},
		'hook preserved nested src fixture outside src/website_md',
		$run_diag );
	ok_with_diag(
		!-e $context->{stale_website_repo_path},
		'hook cleared stale src/website_md output before shared publishing',
		$run_diag
	);

	return;
}

sub assert_website_generated_outputs {
	my ($context) = @_;

	my $helpers = $context->{helpers};
	my $run_diag = $context->{run_diag};

	ok_with_diag( -f $helpers->{ssg_trace_path},
		'fake ssg6 trace was recorded', $run_diag );
	ok_with_diag( -f $helpers->{rssg_trace_path},
		'fake rssg trace was recorded', $run_diag );
	ok_with_diag( -f $context->{trace_path},
		'fake stagit trace was recorded', $run_diag );
	ok_with_diag( -d $context->{stagit_dir},
		'shared stagit output directory exists', $run_diag );
	ok_with_diag( -d $context->{stagit_git_dir},
		'hook cloned the bare repository into src/website_md/.git',
		$run_diag );
	ok_with_diag( -f $context->{head_path},
		'cloned bare repository preserved .git/HEAD', $run_diag );
	ok_with_diag( -f $context->{info_refs_path},
		'git update-server-info populated .git/info/refs', $run_diag );

	for my $entry (
		[
			$context->{root_index_path}, $context->{root_index_gz_path},
			'generated root index.html'
		],
		[
			$context->{about_path}, $context->{about_gz_path},
			'generated root about.txt'
		],
		[
			$context->{rss_path}, $context->{rss_gz_path},
			'generated rss.xml'
		],
		[
			$context->{root_src_path}, $context->{root_src_gz_path},
			'generated src/src.html'
		],
		)
	{
		my ( $path, $gz_path, $label ) = @{$entry};
		ok_with_diag( -f $path, "$label exists", $run_diag );
		ok_with_diag( ( -e $path ? -s $path : 0 ) > $GZIP_THRESHOLD_BYTES,
			"$label exceeds the gzip threshold", $run_diag );
		ok_with_diag( -f $gz_path, "$label was gzipped", $run_diag );
	}

	ok_with_diag( -f $context->{root_other_path},
		'generated src/other.html exists', $run_diag );
	ok_with_diag(
		(
			-e $context->{root_other_path}
			? -s $context->{root_other_path}
			: 0
		) > $GZIP_THRESHOLD_BYTES,
		'generated src/other.html exceeds the gzip threshold',
		$run_diag
	);
	ok_with_diag(
		!-e $context->{root_other_gz_path},
		'generated src/other.html was not gzipped because the website no-src rule only compresses src/src.html inside src/',
		$run_diag
	);
	ok_with_diag(
		!-e $context->{dot_files_path},
		'hook deleted the generated .files marker after website generation',
		$run_diag
	);
	ok_with_diag( -f $context->{root_style_css_path},
		'fake ssg6 recreated root stagit/style.css after website cleanup',
		$run_diag );
	ok_with_diag( -f $context->{root_logo_path},
		'fake ssg6 recreated root stagit/logo.png after website cleanup',
		$run_diag );
	ok_with_diag(
		-f $context->{root_favicon_path},
		'fake ssg6 recreated root stagit/favicon.png after website cleanup',
		$run_diag
	);
	ok_with_diag( -f $context->{copied_style_css_path},
		'shared publishing copied stagit/style.css into src/website_md',
		$run_diag );
	ok_with_diag( -f $context->{copied_logo_path},
		'shared publishing copied stagit/logo.png into src/website_md',
		$run_diag );
	ok_with_diag( -f $context->{copied_favicon_path},
		'shared publishing copied stagit/favicon.png into src/website_md',
		$run_diag );
	ok_with_diag( -f $context->{log_path},
		'fake stagit generated log.html', $run_diag );
	ok_with_diag( -f $context->{index_path},
		'hook copied log.html to index.html', $run_diag );

	return;
}

sub assert_website_helper_traces {
	my ($context) = @_;

	my $harness = $context->{harness};
	my $helpers = $context->{helpers};
	my $repo = $context->{repo};
	my $run_diag = $context->{run_diag};

SKIP: {
		if ( !-f $helpers->{ssg_trace_path}
			|| !-f $helpers->{rssg_trace_path} )
		{
			skip 'website helper traces missing',
				$WEBSITE_HELPER_TRACE_SKIP_COUNT;
		}
		my $ssg_trace =
			$harness->parse_trace_file( $helpers->{ssg_trace_path} );
		my $rssg_trace =
			$harness->parse_trace_file( $helpers->{rssg_trace_path} );
		my $ssg_clone_dir = $rssg_trace->{argv}->[0] =~ s{/index[.]md\z}{}r;

		is_with_diag( $ssg_trace->{self}, $helpers->{ssg_path},
			'fake ssg6 trace recorded the absolute helper path',
			$run_diag );
		is_with_diag(
			$ssg_trace->{cwd},
			$repo->{bare_repo_dir},
			'fake ssg6 trace recorded the bare repository as cwd', $run_diag
		);
		is_deeply(
			$ssg_trace->{argv},
			[
				$ssg_clone_dir, $harness->webroot_dir,
				$context->{website_name}, $context->{domain_with_schema}
			],
			'fake ssg6 trace recorded clone dir, temp webroot, website name, and public domain argv',
		) or diag($run_diag);
		is_with_diag( $rssg_trace->{self}, $helpers->{rssg_path},
			'fake rssg trace recorded the absolute helper path',
			$run_diag );
		is_with_diag(
			$rssg_trace->{cwd},
			$repo->{bare_repo_dir},
			'fake rssg trace recorded the bare repository as cwd', $run_diag
		);
		ok_with_diag( defined $rssg_trace->{argv}->[0],
			'fake rssg trace recorded the index path argv entry',
			$run_diag );
		ok_with_diag( defined $rssg_trace->{argv}->[1],
			'fake rssg trace recorded the website title argv entry',
			$run_diag );
		is_with_diag(
			$rssg_trace->{argv}->[0],
			catfile( $ssg_trace->{argv}->[0], 'index.md' ),
			'fake rssg trace recorded the cloned index.md path derived from the ssg6 clone dir',
			$run_diag,
		);
		is_with_diag(
			$rssg_trace->{argv}->[1],
			$context->{website_title},
			'fake rssg trace recorded the expected website title', $run_diag
		);
		unlike_with_diag(
			$ssg_trace->{argv}->[1],
			qr/^\Q$context->{production_webroot}\E(?:\/|\z)/,
			'fake ssg6 webroot argv does not point at the production webroot',
			$run_diag,
		);
		unlike_with_diag(
			$ssg_trace->{self},
			qr/^\Q$context->{real_helper_bin}\E(?:\/|\z)/,
			'fake ssg6 self path does not point into the caller home helper bin',
			$run_diag,
		);
		unlike_with_diag(
			$rssg_trace->{self},
			qr/^\Q$context->{real_helper_bin}\E(?:\/|\z)/,
			'fake rssg self path does not point into the caller home helper bin',
			$run_diag,
		);
	}

	return;
}

sub assert_website_stagit_trace {
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
			'fake stagit recorded the shared publishing output directory as cwd',
			$run_diag
		);
		is_deeply(
			$trace->{argv},
			[ q{--}, $repo->{bare_repo_dir} ],
			'fake stagit recorded the expected argv for the shared publishing tail'
		) or diag($run_diag);
	}

	return;
}

sub assert_generated_website_contents {
	my ($context) = @_;

	my $harness = $context->{harness};
	my $run_diag = $context->{run_diag};

SKIP: {
		if ( !-f $context->{root_index_path}
			|| !-f $context->{about_path}
			|| !-f $context->{rss_path} )
		{
			skip 'generated website files missing',
				$GENERATED_WEBSITE_SKIP_COUNT;
		}
		my $root_index = $harness->read_file( $context->{root_index_path} );
		my $about = $harness->read_file( $context->{about_path} );
		my $rss = $harness->read_file( $context->{rss_path} );
		contains_with_diag(
			$root_index,
			$context->{domain_with_schema},
			'generated root index.html records the public domain from fake ssg6',
			$run_diag
		);
		contains_with_diag(
			$about,
			"About $context->{website_name} at $context->{domain_with_schema}",
			'generated root about.txt records the fake website metadata',
			$run_diag
		);
		contains_with_diag(
			$rss,
			$context->{website_title},
			'generated rss.xml records the expected website title',
			$run_diag
		);
		contains_with_diag( $rss, 'index.md',
			'generated rss.xml records the cloned index.md path',
			$run_diag );
		ok_with_diag(
			-f $context->{rss_gz_path},
			'generated rss.xml kept its gzip sidecar alongside the deterministic feed',
			$run_diag
		);
	}

	return;
}

sub assert_website_copied_shared_assets {
	my ($context) = @_;

	my $harness = $context->{harness};
	my $run_diag = $context->{run_diag};

SKIP: {
		if ( !-f $context->{root_style_css_path}
			|| !-f $context->{copied_style_css_path}
			|| !-f $context->{root_logo_path}
			|| !-f $context->{copied_logo_path}
			|| !-f $context->{root_favicon_path}
			|| !-f $context->{copied_favicon_path} )
		{
			skip 'copied shared assets missing',
				$COPIED_SHARED_ASSETS_SKIP_COUNT;
		}
		is_with_diag(
			$harness->read_file( $context->{copied_style_css_path} ),
			$harness->read_file( $context->{root_style_css_path} ),
			'shared publishing copied style.css from the website root stagit assets',
			$run_diag,
		);
		is_with_diag(
			$harness->read_file( $context->{copied_logo_path} ),
			$harness->read_file( $context->{root_logo_path} ),
			'shared publishing copied logo.png from the website root stagit assets',
			$run_diag,
		);
		is_with_diag(
			$harness->read_file( $context->{copied_favicon_path} ),
			$harness->read_file( $context->{root_favicon_path} ),
			'shared publishing copied favicon.png from the website root stagit assets',
			$run_diag,
		);
	}

	return;
}

sub assert_website_log_and_index {
	my ($context) = @_;

	my $harness = $context->{harness};
	my $repo = $context->{repo};
	my $run_diag = $context->{run_diag};

SKIP: {
		if ( !-f $context->{log_path} || !-f $context->{index_path} ) {
			skip 'log.html or index.html missing', $LOG_INDEX_SYNC_SKIP_COUNT;
		}
		my $log_html = $harness->read_file( $context->{log_path} );
		my $index_html = $harness->read_file( $context->{index_path} );
		is_with_diag(
			$index_html,
			$log_html,
			'src/website_md/index.html matches the fake stagit log.html after the shared publishing tail',
			$run_diag
		);
		contains_with_diag(
			$log_html,
			$repo->{bare_repo_dir},
			'fake stagit log.html records the bare repository path for website_md',
			$run_diag
		);
	}

	return;
}

sub assert_website_verbose_output {
	my ($context) = @_;

	my $harness = $context->{harness};
	my $helpers = $context->{helpers};
	my $repo = $context->{repo};
	my $result = $context->{result};
	my $run_diag = $context->{run_diag};
	my $stdout = $result->{stdout};

	contains_with_diag(
		$stdout,
		'WEB SERVER DIRECTORY: ' . $harness->webroot_dir,
		'verbose output names the temp webroot as the active web server directory',
		$run_diag,
	);
	contains_with_diag(
		$stdout,
		'BINARY DIRECTORY: ' . $context->{expected_bindir},
		'verbose output uses the isolated HOME helper-bin path', $run_diag,
	);
	contains_with_diag(
		$stdout,
		'SSG LOCATION: ' . $helpers->{ssg_path},
		'verbose output records the absolute fake ssg6 helper path',
		$run_diag,
	);
	contains_with_diag(
		$stdout,
		'RSSG LOCATION: ' . $helpers->{rssg_path},
		'verbose output records the absolute fake rssg helper path',
		$run_diag,
	);
	contains_with_diag(
		$stdout,
		'Clearing out ' . $harness->webroot_dir . ' (excluding src)',
		'verbose output records the website-specific cleanup that preserves src',
		$run_diag,
	);
	contains_with_diag(
		$stdout,
		'RSS FEED LOCATION: ' . $context->{rss_path},
		'verbose output records the rss.xml output path', $run_diag,
	);
	contains_with_diag(
		$stdout,
		'Deleting ' . $context->{dot_files_path},
		'verbose output records deletion of the generated .files marker',
		$run_diag,
	);
	contains_with_diag(
		$stdout,
		'Gzipping files in '
			. $harness->webroot_dir
			. ' (excluding those in src)',
		'verbose output records the website gzip step that excludes most src content',
		$run_diag,
	);
	contains_with_diag(
		$stdout,
		'STAGIT DIRECTORY: ' . $context->{stagit_dir},
		'verbose output names the shared stagit output directory for website_md',
		$run_diag,
	);
	contains_with_diag(
		$stdout,
		"Running 'stagit -- $repo->{bare_repo_dir}'",
		'verbose output records the fake stagit invocation for the shared publishing tail',
		$run_diag,
	);
	does_not_contain_with_diag(
		$stdout,
		'WEB SERVER DIRECTORY: ' . $context->{production_webroot},
		'verbose output does not report the production webroot as active',
		$run_diag,
	);
	does_not_contain_with_diag(
		$stdout,
		'BINARY DIRECTORY: ' . $context->{real_helper_bin},
		'verbose output does not report the caller real helper-bin path',
		$run_diag,
	);

	return;
}

sub test_website_md_success {
	subtest
		'website_md branch uses isolated helpers and preserves shared publishing tail'
		=> sub {
			my $harness = PostReceive::TestHarness->new;
			my $prereq_diag = join "\n",
			'Install the missing prerequisite on PATH before running this website_md characterization test.',
			'The test expects real git, fake stagit on the harness PATH, and fake ssg6/rssg at the isolated HOME absolute paths.',
			$harness->workspace_diag,
			;

			my $helpers = setup_or_return( 'install fake website helpers',
				sub { install_fake_website_helpers($harness) }, $harness, );
			if ( !$helpers ) {
				return;
			}

			my $fake_stagit = setup_or_return( 'install fake stagit',
				sub { $harness->install_fake_stagit }, $harness, );
			if ( !$fake_stagit ) {
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
				$fake_stagit->{fake_stagit_path},
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

			is_with_diag(
				$harness->executable_in_dir( $helpers->{bindir}, 'ssg6' ),
				$helpers->{ssg_path},
				'fake ssg6 resolves at the isolated HOME absolute path',
				$prereq_diag,
			);
			is_with_diag(
				$harness->executable_in_dir( $helpers->{bindir}, 'rssg' ),
				$helpers->{rssg_path},
				'fake rssg resolves at the isolated HOME absolute path',
				$prereq_diag,
			);

			my $repo = setup_or_return(
				'create website_md bare repository fixture',
				sub {
					$harness->create_bare_repo(
						repo_name => 'website_md.git',
						file_rel => 'index.md',
						file_content =>
						"# Website fixture\n\nThis is a deterministic website fixture.\n",
						commit_message => 'Initial website fixture commit',
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
			my $website_title =
			'My Unix blog: scripts, software, /etc - anthesis';
			my $domain_with_schema = 'https://www.anthes.is';
			my $website_name = 'anthesis';
			my $stagit_dir =
			catdir( $harness->webroot_dir, qw(src website_md) );
			my $stagit_git_dir = catdir( $stagit_dir, '.git' );
			my $head_path = catfile( $stagit_git_dir, 'HEAD' );
			my $info_refs_path = catfile( $stagit_git_dir, qw(info refs) );
			my $root_index_path =
			catfile( $harness->webroot_dir, 'index.html' );
			my $root_index_gz_path =
			catfile( $harness->webroot_dir, 'index.html.gz' );
			my $about_path = catfile( $harness->webroot_dir, 'about.txt' );
			my $about_gz_path =
			catfile( $harness->webroot_dir, 'about.txt.gz' );
			my $dot_files_path = catfile( $harness->webroot_dir, '.files' );
			my $rss_path = catfile( $harness->webroot_dir, 'rss.xml' );
			my $rss_gz_path = catfile( $harness->webroot_dir, 'rss.xml.gz' );
			my $root_src_path =
			catfile( $harness->webroot_dir, qw(src src.html) );
			my $root_src_gz_path =
			catfile( $harness->webroot_dir, qw(src src.html.gz) );
			my $root_other_path =
			catfile( $harness->webroot_dir, qw(src other.html) );
			my $root_other_gz_path =
			catfile( $harness->webroot_dir, qw(src other.html.gz) );
			my $root_style_css_path =
			catfile( $harness->webroot_dir, qw(stagit style.css) );
			my $root_logo_path =
			catfile( $harness->webroot_dir, qw(stagit logo.png) );
			my $root_favicon_path =
			catfile( $harness->webroot_dir, qw(stagit favicon.png) );
			my $copied_style_css_path = catfile( $stagit_dir, 'style.css' );
			my $copied_logo_path = catfile( $stagit_dir, 'logo.png' );
			my $copied_favicon_path = catfile( $stagit_dir, 'favicon.png' );
			my $log_path = catfile( $stagit_dir, 'log.html' );
			my $index_path = catfile( $stagit_dir, 'index.html' );
			my $trace_path = $harness->fake_stagit_trace_path;
			my $stale_root_path =
			catfile( $harness->webroot_dir, 'stale-root.txt' );
			my $stale_root_nested_path =
			catfile( $harness->webroot_dir, qw(stale-dir nested.txt) );
			my $stale_root_stagit_path =
			catfile( $harness->webroot_dir, qw(stagit stale-before-run.txt) );
			my $preserved_src_path =
			catfile( $harness->webroot_dir, qw(src keep-existing.txt) );
			my $preserved_other_repo_path =
			catfile( $harness->webroot_dir, qw(src existing-repo keep.txt) );
			my $stale_website_repo_path =
			catfile( $stagit_dir, 'stale-before-run.txt' );

			setup_or_return(
				'seed stale and preserved webroot fixtures',
				sub {
					$harness->write_file(
						path => $stale_root_path,
						content => "remove this stale root file\n",
					);
					$harness->write_file(
						path => $stale_root_nested_path,
						content => "remove this stale nested root file\n",
					);
					$harness->write_file(
						path => $stale_root_stagit_path,
						content =>
						"stale root stagit asset should be removed\n",
					);
					$harness->write_file(
						path => $preserved_src_path,
						content =>
						"keep this src fixture outside src/website_md\n",
					);
					$harness->write_file(
						path => $preserved_other_repo_path,
						content =>
						"keep this nested src fixture outside src/website_md\n",
					);
					$harness->write_file(
						path => $stale_website_repo_path,
						content =>
						"stale website_md output should be cleared before shared publishing\n",
					);
					return 1;
				},
				$harness,
			) or return;

			my $result = $harness->run_post_receive( argv => ['-v'] );
			my $run_diag =
			run_diag_with_helper_traces( $harness, $result, $helpers );

			my %assert_context = (
				about_gz_path => $about_gz_path,
				about_path => $about_path,
				copied_favicon_path => $copied_favicon_path,
				copied_logo_path => $copied_logo_path,
				copied_style_css_path => $copied_style_css_path,
				domain_with_schema => $domain_with_schema,
				dot_files_path => $dot_files_path,
				expected_bindir => $expected_bindir,
				helpers => $helpers,
				harness => $harness,
				head_path => $head_path,
				index_path => $index_path,
				info_refs_path => $info_refs_path,
				log_path => $log_path,
				preserved_other_repo_path => $preserved_other_repo_path,
				preserved_src_path => $preserved_src_path,
				production_webroot => $production_webroot,
				real_helper_bin => $real_helper_bin,
				repo => $repo,
				result => $result,
				root_favicon_path => $root_favicon_path,
				root_index_gz_path => $root_index_gz_path,
				root_index_path => $root_index_path,
				root_logo_path => $root_logo_path,
				root_other_gz_path => $root_other_gz_path,
				root_other_path => $root_other_path,
				root_src_gz_path => $root_src_gz_path,
				root_src_path => $root_src_path,
				root_style_css_path => $root_style_css_path,
				rss_gz_path => $rss_gz_path,
				rss_path => $rss_path,
				run_diag => $run_diag,
				stagit_dir => $stagit_dir,
				stagit_git_dir => $stagit_git_dir,
				stale_root_nested_path => $stale_root_nested_path,
				stale_root_path => $stale_root_path,
				stale_root_stagit_path => $stale_root_stagit_path,
				stale_website_repo_path => $stale_website_repo_path,
				trace_path => $trace_path,
				website_name => $website_name,
				website_title => $website_title,
			);

			assert_website_hook_success( \%assert_context );
			assert_website_workspace_isolation( \%assert_context );
			assert_website_cleanup_preservation( \%assert_context );
			assert_website_generated_outputs( \%assert_context );
			assert_website_helper_traces( \%assert_context );
			assert_website_stagit_trace( \%assert_context );
			assert_generated_website_contents( \%assert_context );
			assert_website_copied_shared_assets( \%assert_context );
			assert_website_log_and_index( \%assert_context );
			assert_website_verbose_output( \%assert_context );

			done_testing();
		};

	return;
}

sub test_website_md_ssg6_late_failure {
	subtest
		'website_md fails before shared publishing when ssg6 exits non-zero after side effects'
		=> sub {
			my $harness = PostReceive::TestHarness->new;
			my $prereq_diag = join "\n",
			'Install the missing prerequisite on PATH before running this website_md failure test.',
			'The test expects real git, fake stagit on the harness PATH, and fake ssg6/rssg at the isolated HOME absolute paths.',
			$harness->workspace_diag,
			;

			my $helpers = setup_or_return(
				'install fake website helpers with late ssg6 failure',
				sub {
					install_fake_website_helpers( $harness,
						ssg_exit_after_side_effects =>
						$SSG_LATE_FAILURE_EXIT_CODE, );
				},
				$harness,
			);
			if ( !$helpers ) {
				return;
			}

			my $fake_stagit = setup_or_return( 'install fake stagit',
				sub { $harness->install_fake_stagit }, $harness, );
			if ( !$fake_stagit ) {
				return;
			}

			my $real_git = $harness->executable_on_path('git');
			ok_with_diag( defined $real_git,
				'real git executable available on harness PATH', $prereq_diag );
			if ( !defined $real_git ) {
				return;
			}

			my $repo = setup_or_return(
				'create website_md bare repository fixture',
				sub {
					$harness->create_bare_repo(
						repo_name => 'website_md.git',
						file_rel => 'index.md',
						file_content =>
						"# Website fixture\n\nThis is a deterministic website fixture.\n",
						commit_message => 'Initial website fixture commit',
					);
				},
				$harness,
			);
			if ( !$repo ) {
				return;
			}

			my $root_index_path =
			catfile( $harness->webroot_dir, 'index.html' );
			my $root_style_css_path =
			catfile( $harness->webroot_dir, qw(stagit style.css) );
			my $trace_path = $harness->fake_stagit_trace_path;

			my $result = $harness->run_post_receive( argv => ['-v'] );
			my $run_diag =
			run_diag_with_helper_traces( $harness, $result, $helpers );

			is_with_diag( $result->{command}->[0],
				$harness->hook_path, 'hook ran via executable child path',
				$run_diag );
			ok_with_diag(
				$result->{status} != 0,
				'hook child status is non-zero when ssg6 exits 42 after side effects',
				$run_diag,
			);
			ok_with_diag(
				$result->{exit_code} != 0,
				'hook exit code is non-zero when ssg6 exits 42 after side effects',
				$run_diag,
			);
			is_with_diag( $result->{signal}, 0,
				'hook terminated without signal after ssg6 failure',
				$run_diag );
			like_with_diag( $result->{stderr}, qr/\bssg6\b/,
				'stderr names the failing ssg6 helper', $run_diag );
			contains_with_diag( $result->{stderr}, $SSG_LATE_FAILURE_EXIT_CODE,
				'stderr reports the failing ssg6 exit status', $run_diag );
			ok_with_diag( -f $helpers->{ssg_trace_path},
				'fake ssg6 trace was recorded before the helper failed',
				$run_diag );
			ok_with_diag( -f $root_index_path,
				'fake ssg6 created root index.html before exiting non-zero',
				$run_diag );
			ok_with_diag(
				-f $root_style_css_path,
				'fake ssg6 created shared stagit/style.css before exiting non-zero',
				$run_diag,
			);
			ok_with_diag( !-e $trace_path,
				'shared stagit publishing did not run after ssg6 exited 42',
				$run_diag, );

			done_testing();
		};

	return;
}

sub test_website_md_rssg_late_failure {
	subtest
		'website_md fails before shared publishing when rssg exits non-zero after partial output'
		=> sub {
			my $harness = PostReceive::TestHarness->new;
			my $prereq_diag = join "\n",
			'Install the missing prerequisite on PATH before running this website_md failure test.',
			'The test expects real git, fake stagit on the harness PATH, and fake ssg6/rssg at the isolated HOME absolute paths.',
			$harness->workspace_diag,
			;

			my $helpers = setup_or_return(
				'install fake website helpers with late rssg failure',
				sub {
					install_fake_website_helpers( $harness,
						rssg_exit_after_partial_output =>
						$RSSG_LATE_FAILURE_EXIT_CODE, );
				},
				$harness,
			);
			if ( !$helpers ) {
				return;
			}

			my $fake_stagit = setup_or_return( 'install fake stagit',
				sub { $harness->install_fake_stagit }, $harness, );
			if ( !$fake_stagit ) {
				return;
			}

			my $real_git = $harness->executable_on_path('git');
			ok_with_diag( defined $real_git,
				'real git executable available on harness PATH', $prereq_diag );
			if ( !defined $real_git ) {
				return;
			}

			my $repo = setup_or_return(
				'create website_md bare repository fixture',
				sub {
					$harness->create_bare_repo(
						repo_name => 'website_md.git',
						file_rel => 'index.md',
						file_content =>
						"# Website fixture\n\nThis is a deterministic website fixture.\n",
						commit_message => 'Initial website fixture commit',
					);
				},
				$harness,
			);
			if ( !$repo ) {
				return;
			}

			my $rss_path = catfile( $harness->webroot_dir, 'rss.xml' );
			my $trace_path = $harness->fake_stagit_trace_path;

			my $result = $harness->run_post_receive( argv => ['-v'] );
			my $run_diag =
			run_diag_with_helper_traces( $harness, $result, $helpers );

			is_with_diag( $result->{command}->[0],
				$harness->hook_path, 'hook ran via executable child path',
				$run_diag );
			ok_with_diag(
				$result->{status} != 0,
				'hook child status is non-zero when rssg exits 43 after partial output',
				$run_diag,
			);
			ok_with_diag(
				$result->{exit_code} != 0,
				'hook exit code is non-zero when rssg exits 43 after partial output',
				$run_diag,
			);
			is_with_diag( $result->{signal}, 0,
				'hook terminated without signal after rssg failure',
				$run_diag );
			like_with_diag( $result->{stderr}, qr/\brssg\b/,
				'stderr names the failing rssg helper', $run_diag );
			contains_with_diag( $result->{stderr}, $RSSG_LATE_FAILURE_EXIT_CODE,
				'stderr reports the failing rssg exit status', $run_diag );
			ok_with_diag( -f $helpers->{ssg_trace_path},
				'fake ssg6 trace was recorded before rssg failed', $run_diag );
			ok_with_diag( -f $helpers->{rssg_trace_path},
				'fake rssg trace was recorded before the helper failed',
				$run_diag );
			ok_with_diag( -f $rss_path,
				'fake rssg wrote partial rss.xml before exiting non-zero',
				$run_diag );
			ok_with_diag(
				( -e $rss_path ? -s $rss_path : 0 ) > $GZIP_THRESHOLD_BYTES,
				'partial rss.xml contains enough output for the current hook to keep going',
				$run_diag,
			);
			ok_with_diag( !-e $trace_path,
				'shared stagit publishing did not run after rssg exited 43',
				$run_diag, );

			done_testing();
		};

	return;
}

test_website_md_success();
test_website_md_ssg6_late_failure();
test_website_md_rssg_late_failure();
done_testing();
