#!/usr/bin/env perl
use strict;
use warnings;

use File::Basename qw(dirname);
use File::Spec;
use File::Spec::Functions qw(catdir catfile);
use Test::More;
use lib File::Spec->catdir( dirname( File::Spec->rel2abs(__FILE__) ), 'lib' );

use PostReceive::TestHarness;

# These tests pin the dependency-check contract for the website_md branch.
# The hook invokes ssg6 and rssg via absolute HOME/.local/bin paths, so the
# usual PATH-based `which` probe in check_dependencies cannot catch them. The
# branch must fail fast with a message that names the missing helper *before*
# clearing the webroot, cloning the source, or invoking any helper, so that a
# misconfigured host cannot lose the published site to a partial run.
#
# The dotfiles branch deliberately stays out of these checks because its
# action replaces ssg6/rssg in place; requiring them to pre-exist would block
# the first dotfiles deploy.

sub install_executable_stub {
	my ( $harness, %args ) = @_;

	my $path = $args{path}
		or die "install_executable_stub requires a path\n";
	my $script = "#!/usr/bin/env perl\nuse strict;\nuse warnings;\nexit 0;\n";

	$harness->write_file( path => $path, content => $script );
	chmod 0700, $path
		or die "Could not chmod 0700 $path: $!\n";

	return $path;
}

sub setup_website_md_repo {
	my ($harness) = @_;

	return $harness->create_bare_repo(
		repo_name      => 'website_md.git',
		file_rel       => 'index.md',
		file_content   => "# website_md helper-check fixture\n",
		commit_message => 'Initial helper-check fixture commit',
	);
}

sub seed_preserved_webroot_marker {
	my ( $harness, $relative ) = @_;

	my $absolute = catfile( $harness->webroot_dir, $relative );
	$harness->write_file(
		path    => $absolute,
		content => "this file must survive a failed helper-check run\n",
	);
	return $absolute;
}

subtest 'website_md push fails fast with a clear error when ssg6 is missing' => sub {
	my $harness = PostReceive::TestHarness->new;
	$harness->install_fake_stagit;

	my $bindir = $harness->ensure_dir(
		catdir( $harness->home_dir, qw(.local bin) )
	);
	my $expected_ssg_path = catfile( $bindir, 'ssg6' );
	my $rssg_path = catfile( $bindir, 'rssg' );
	install_executable_stub( $harness, path => $rssg_path );

	ok( !-e $expected_ssg_path, 'ssg6 is absent for this fixture' );
	ok( -x $rssg_path, 'rssg stub is installed and executable' );

	my $repo = setup_website_md_repo($harness);
	my $preserved_marker = seed_preserved_webroot_marker(
		$harness, 'preserved-before-run.txt',
	);

	my $result = $harness->run_post_receive( argv => ['-v'] );
	my $diag = $harness->describe_run($result);

	isnt(
		$result->{exit_code}, 0,
		'hook exits non-zero when ssg6 is missing'
	) or diag($diag);

	like(
		$result->{stderr},
		qr/\Q$expected_ssg_path\E/,
		'stderr names the missing ssg6 helper path',
	) or diag($diag);

	ok(
		-f $preserved_marker,
		'hook fails before clearing the webroot when ssg6 is missing',
	) or diag($diag);

	ok(
		!-e $harness->fake_stagit_trace_path,
		'hook fails before invoking the shared stagit publishing tail',
	) or diag($diag);
};

subtest 'website_md push fails fast with a clear error when rssg is missing' => sub {
	my $harness = PostReceive::TestHarness->new;
	$harness->install_fake_stagit;

	my $bindir = $harness->ensure_dir(
		catdir( $harness->home_dir, qw(.local bin) )
	);
	my $ssg_path = catfile( $bindir, 'ssg6' );
	install_executable_stub( $harness, path => $ssg_path );
	my $expected_rssg_path = catfile( $bindir, 'rssg' );

	ok( -x $ssg_path, 'ssg6 stub is installed and executable' );
	ok( !-e $expected_rssg_path, 'rssg is absent for this fixture' );

	my $repo = setup_website_md_repo($harness);
	my $preserved_marker = seed_preserved_webroot_marker(
		$harness, 'preserved-before-run.txt',
	);

	my $result = $harness->run_post_receive( argv => ['-v'] );
	my $diag = $harness->describe_run($result);

	isnt(
		$result->{exit_code}, 0,
		'hook exits non-zero when rssg is missing'
	) or diag($diag);

	like(
		$result->{stderr},
		qr/\Q$expected_rssg_path\E/,
		'stderr names the missing rssg helper path',
	) or diag($diag);

	ok(
		-f $preserved_marker,
		'hook fails before clearing the webroot when rssg is missing',
	) or diag($diag);

	ok(
		!-e $harness->fake_stagit_trace_path,
		'hook fails before invoking the shared stagit publishing tail',
	) or diag($diag);
};

done_testing();
