#!/usr/bin/env perl
use strict;
use warnings;

use File::Basename qw(dirname);
use File::Spec;
use File::Spec::Functions qw(catdir catfile rootdir);
use Test::More;
use lib File::Spec->catdir( dirname( File::Spec->rel2abs(__FILE__) ), 'lib' );

use PostReceive::TestHarness;

sub setup_or_stop {
	my ( $label, $code, $harness ) = @_;

	my $value = eval { $code->() };
	if ( !$@ ) {
		pass($label);
		return $value;
	}

	fail($label);
	diag($@);
	diag( $harness->describe_workspace );
	done_testing();
	exit 1;
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

my $harness = PostReceive::TestHarness->new;
my $assets = setup_or_stop(
	'seed shared stagit assets',
	sub { $harness->seed_stagit_assets },
	$harness,
);
setup_or_stop(
	'install fake stagit',
	sub { $harness->install_fake_stagit },
	$harness,
);
my $repo = setup_or_stop(
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

subtest 'public helper surface exposes workspace, file, executable, trace, and mode mechanics' => sub {
	my $workspace_diag = $harness->describe_workspace;

	is_with_diag(
		$harness->workspace_diag,
		$workspace_diag,
		'workspace_diag aliases describe_workspace',
		$workspace_diag,
	);

	for my $diag_line (
		'workspace_dir: ' . $harness->workspace_dir,
		'home_dir: ' . $harness->home_dir,
		'webroot_dir: ' . $harness->webroot_dir,
		'fake_command_dir: ' . $harness->fake_command_dir,
		'repo_fixture_root: ' . $harness->repo_fixture_root,
		'PATH: ' . $harness->path,
	) {
		like_with_diag(
			$workspace_diag,
			qr/^\Q$diag_line\E$/m,
			"describe_workspace includes $diag_line",
			$workspace_diag,
		);
	}

	my $ensured_dir = $harness->ensure_dir(
		catdir( qw(helper-check nested parent) )
	);
	ok_with_diag( -d $ensured_dir, 'ensure_dir creates a nested relative directory', $workspace_diag );
	like_with_diag(
		$ensured_dir,
		qr/^\Q@{[ $harness->workspace_dir ]}\E(?:\/|\z)/,
		'ensure_dir resolves relative directories under the harness workspace',
		$workspace_diag,
	);

	my $text_path = $harness->write_file(
		path    => catfile( qw(helper-check nested parent child note.txt) ),
		content => "helper file content\n",
	);
	ok_with_diag( -f $text_path, 'write_file creates missing parent directories for relative paths', $workspace_diag );
	is_with_diag(
		$harness->read_file($text_path),
		"helper file content\n",
		'write_file stores text content that read_file can read back',
		$workspace_diag,
	);

	my $binary_payload = "\x00helper\xFF\n";
	my $binary_path = $harness->write_file(
		path    => catfile( qw(helper-check nested parent payload.bin) ),
		content => $binary_payload,
		binary  => 1,
	);
	is_with_diag(
		$harness->read_file($binary_path),
		$binary_payload,
		'write_file preserves binary content',
		$workspace_diag,
	);

	my $helper_tool_path = $harness->write_file(
		path    => catfile( qw(helper-check bin helper-tool) ),
		content => "#!/bin/sh\nexit 0\n",
	);
	chmod 0700, $helper_tool_path
		or die "Could not chmod 0700 $helper_tool_path: $!\n";

	is_with_diag(
		$harness->executable_on_path('stagit'),
		$harness->fake_stagit_path,
		'executable_on_path finds the fake stagit shim on the harness PATH',
		$workspace_diag,
	);
	is_with_diag(
		$harness->executable_on_path( 'helper-tool', path => catdir( qw(helper-check bin) ) ),
		$helper_tool_path,
		'executable_on_path resolves relative PATH entries under the harness workspace',
		$workspace_diag,
	);
	is_with_diag(
		$harness->executable_in_dir( catdir( qw(helper-check bin) ), 'helper-tool' ),
		$helper_tool_path,
		'executable_in_dir resolves relative directories under the harness workspace',
		$workspace_diag,
	);
	ok_with_diag(
		!defined $harness->executable_on_path('missing-helper'),
		'executable_on_path returns undef for a missing executable',
		$workspace_diag,
	);
	ok_with_diag(
		!defined $harness->executable_in_dir( catdir( qw(helper-check bin) ), 'missing-helper' ),
		'executable_in_dir returns undef for a missing executable',
		$workspace_diag,
	);

	my $trace_text = join(
		"\n",
		'cwd=/tmp/helper-trace',
		'argv[0]=--',
		'argv[1]=repos/example.git',
		'helper=fake-stagit',
		'trace.version=1',
		'malformed line without equals',
		'argv[bad]=ignored',
		q{},
	);
	my $parsed_trace = $harness->parse_trace($trace_text);
	is_deeply(
		$parsed_trace,
		{
			argv            => [ '--', 'repos/example.git' ],
			cwd             => '/tmp/helper-trace',
			helper          => 'fake-stagit',
			'trace.version' => '1',
		},
		'parse_trace captures argv and generic key lines while ignoring malformed input',
	) or diag($workspace_diag);

	my $trace_file = $harness->write_file(
		path    => catfile( qw(helper-check traces sample.trace) ),
		content => $trace_text,
	);
	is_deeply(
		$harness->parse_trace_file($trace_file),
		$parsed_trace,
		'parse_trace_file reads and parses a harness-owned absolute trace path',
	) or diag($workspace_diag);

	is_with_diag(
		$harness->file_mode_octal( catfile( qw(helper-check bin helper-tool) ) ),
		'0700',
		'file_mode_octal reports executable mode for a relative harness path',
		$workspace_diag,
	);
	ok_with_diag(
		!defined $harness->file_mode_octal( catfile( qw(helper-check missing mode.txt) ) ),
		'file_mode_octal returns undef for a missing file',
		$workspace_diag,
	);
	done_testing();
};

my $result = $harness->run_post_receive( argv => ['-v'] );
my $run_diag = $harness->describe_run($result);

my $production_webroot = catdir( rootdir(), qw(var www htdocs www.anthes.is) );
my $real_helper_bin = catdir( ( $ENV{HOME} // q{} ), qw(.local bin) );
my $expected_bindir = catdir( $harness->home_dir, qw(.local bin) );
my $expected_url = 'https://www.anthes.is/src/learning_perl_exercises/.git';
my $stagit_dir = catdir( $harness->webroot_dir, qw(src learning_perl_exercises) );
my $owner_path = catfile( $repo->{bare_repo_dir}, 'owner' );
my $description_path = catfile( $repo->{bare_repo_dir}, 'description' );
my $url_path = catfile( $repo->{bare_repo_dir}, 'url' );
my $trace_path = $harness->fake_stagit_trace_path;
my $log_path = catfile( $stagit_dir, 'log.html' );
my $index_path = catfile( $stagit_dir, 'index.html' );
my $css_path = catfile( $stagit_dir, 'style.css' );
my $logo_path = catfile( $stagit_dir, 'logo.png' );
my $favicon_path = catfile( $stagit_dir, 'favicon.png' );

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

ok_with_diag( -f $owner_path, 'owner metadata file exists', $run_diag );
ok_with_diag( -f $description_path, 'description metadata file exists', $run_diag );
ok_with_diag( -f $url_path, 'url metadata file exists', $run_diag );

SKIP: {
	skip 'metadata file missing', 3 unless -f $owner_path && -f $description_path && -f $url_path;
	my $owner = $harness->read_file($owner_path);
	my $description = $harness->read_file($description_path);
	my $url = $harness->read_file($url_path);

	like_with_diag( $owner, qr/Ashlen/, 'owner metadata names Ashlen', $run_diag );
	like_with_diag(
		$description,
		qr/Learning Perl exercises/,
		'description metadata names Learning Perl exercises',
		$run_diag,
	);
	like_with_diag( $url, qr/\Q$expected_url\E/, 'url metadata uses the public clone URL', $run_diag );
}

ok_with_diag( -d $stagit_dir, 'common repository output directory exists under the temp webroot', $run_diag );
ok_with_diag( -f $trace_path, 'fake stagit trace was recorded', $run_diag );
ok_with_diag( -f $log_path, 'fake stagit generated log.html', $run_diag );
ok_with_diag( -f $index_path, 'hook copied log.html to index.html', $run_diag );
ok_with_diag( -f $css_path, 'hook copied shared style.css into stagit output', $run_diag );
ok_with_diag( -f $logo_path, 'hook copied shared logo.png into stagit output', $run_diag );
ok_with_diag( -f $favicon_path, 'hook copied shared favicon.png into stagit output', $run_diag );

SKIP: {
	skip 'log.html or index.html missing', 2 unless -f $log_path && -f $index_path;
	my $log_html = $harness->read_file($log_path);
	my $index_html = $harness->read_file($index_path);
	is_with_diag( $index_html, $log_html, 'index.html matches the generated log.html', $run_diag );
	like_with_diag( $log_html, qr/\Q$repo->{bare_repo_dir}\E/, 'fake stagit log.html records the bare repo path', $run_diag );
}

SKIP: {
	skip 'copied assets missing', 3 unless -f $css_path && -f $logo_path && -f $favicon_path;
	is_with_diag(
		$harness->read_file($css_path),
		$harness->read_file( $assets->{style_css_path} ),
		'style.css was copied from the seeded stagit asset',
		$run_diag,
	);
	is_with_diag(
		$harness->read_file($logo_path),
		$harness->read_file( $assets->{logo_png_path} ),
		'logo.png was copied from the seeded stagit asset',
		$run_diag,
	);
	is_with_diag(
		$harness->read_file($favicon_path),
		$harness->read_file( $assets->{favicon_png_path} ),
		'favicon.png was copied from the seeded stagit asset',
		$run_diag,
	);
}

SKIP: {
	skip 'fake stagit trace missing', 2 unless -f $trace_path;
	my $trace = $harness->parse_trace_file($trace_path);
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
