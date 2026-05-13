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

Readonly::Scalar my $STALE_SSG6_MODE => oct '0644';
Readonly::Scalar my $STALE_SSG6_MODE_TEXT => '0644';
Readonly::Scalar my $STALE_RSSG_MODE => oct '0600';
Readonly::Scalar my $STALE_RSSG_MODE_TEXT => '0600';
Readonly::Scalar my $SYSADM_FIXTURE_CONTENT_SKIP_COUNT => 2;
Readonly::Scalar my $STAGIT_TRACE_SKIP_COUNT => 2;
Readonly::Scalar my $LOG_INDEX_SYNC_SKIP_COUNT => 1;
Readonly::Scalar my $DOTFILES_HELPER_REPLACEMENT_SKIP_COUNT => 4;

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

sub run_diag_with_sysadm_target {
	my ( $harness, $result, $sysadm_target_dir ) = @_;
	my $production_sysadm_dir = catdir( rootdir(), qw(etc sysadm) );

	return join "\n",
		$harness->describe_run($result),
		'sysadm_target_dir: ' . $sysadm_target_dir,
		'production_sysadm_dir: ' . $production_sysadm_dir,
		'PATH: ' . $harness->path;
}

sub run_append_validation_subtest {
	subtest
		'append_to_work_clone rejects invalid file lists before running git' =>
		sub {
			my $harness = PostReceive::TestHarness->new;
			my $repo = setup_or_return(
				'create bare repository fixture for append validation',
				sub {
					$harness->create_bare_repo(
						repo_name => 'append-validation.git',
						file_rel => 'README.md',
						file_content => "append validation fixture\n",
					);
				},
				$harness,
			);
			if ( !$repo ) {
				return;
			}

			my $initial_command_count = scalar @{ $harness->command_results };
			my $ok = eval {
				$harness->append_to_work_clone(
					work_clone_dir => $repo->{work_clone_dir},
					files => [],
				);
				1;
			};

			ok( !$ok, 'empty append file list is rejected' )
			or diag( $harness->workspace_diag );
			contains_with_diag(
				$EVAL_ERROR,
				'append_to_work_clone requires a non-empty files array reference',
				'append validation names the missing files input',
				$harness->workspace_diag,
			);
			is(
				scalar @{ $harness->command_results },
				$initial_command_count,
				'invalid append arguments fail before any git commands run',
			) or diag( $harness->workspace_diag );

			my $escaped_file_rel = catfile(qw(.. escaped.txt));
			$ok = eval {
				$harness->append_to_work_clone(
					work_clone_dir => $repo->{work_clone_dir},
					files => [
						{
							file_rel => $escaped_file_rel,
							content => "escape attempt\n",
						},
					],
				);
				1;
			};

			ok( !$ok, 'append rejects file paths that escape the work clone' )
			or diag( $harness->workspace_diag );
			contains_with_diag(
				$EVAL_ERROR,
				'append_to_work_clone file_rel must stay within the work clone',
				'append validation names the escaping file_rel field',
				$harness->workspace_diag,
			);
			contains_with_diag( $EVAL_ERROR, $escaped_file_rel,
				'append validation names the rejected escaping file path',
				$harness->workspace_diag, );
			is(
				scalar @{ $harness->command_results },
				$initial_command_count,
				'escaping append paths fail before any git commands run',
			) or diag( $harness->workspace_diag );

			done_testing();
		};

	return;
}

sub run_sysadm_deployment_subtest {
	subtest
		'sysadm branch uses contained deployment target and preserves shared publishing tail'
		=> sub {
			my $harness = PostReceive::TestHarness->new;
			my $prereq_diag = join "\n",
			'Install the missing prerequisite on PATH before running this sysadm branch characterization test.',
			'The test expects real git plus a fake stagit shim that is prepended on PATH.',
			$harness->workspace_diag;

			my $assets = setup_or_return( 'seed shared stagit assets',
				sub { $harness->seed_stagit_assets }, $harness, );
			if ( !$assets ) {
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

			my $repo = setup_or_return(
				'create sysadm bare repository fixture',
				sub {
					$harness->create_bare_repo(
						repo_name => 'sysadm.git',
						file_rel => 'README.md',
						file_content => "sysadm fixture README\n",
					);
				},
				$harness,
			);
			if ( !$repo ) {
				return;
			}

			my $added_sysadm_fixture = setup_or_return(
				'add nested sysadm deployment fixture',
				sub {
					$harness->append_to_work_clone(
						work_clone_dir => $repo->{work_clone_dir},
						commit_message => 'Add nested sysadm fixture',
						files => [
							{
								file_rel => catfile(qw(roles web config.txt)),
								content => "listen=127.0.0.1\n",
							},
						],
					);
					return 1;
				},
				$harness,
			);
			if ( !$added_sysadm_fixture ) {
				return;
			}

			my $sysadm_target_dir = setup_or_return(
				'create disposable sysadm target (the hook expects the target directory to already exist)',
				sub {
					my $dir = $harness->ensure_dir(
						catdir( $harness->workspace_dir, 'sysadm-target' ) );
					$harness->write_file(
						path => catfile( $dir, 'stale-before-run.txt' ),
						content => "remove this stale sysadm file\n",
					);
					$harness->write_file(
						path => catfile( $dir, qw(stale-dir nested.txt) ),
						content => "remove this stale sysadm directory entry\n",
					);
					return $dir;
				},
				$harness,
			);
			if ( !$sysadm_target_dir ) {
				return;
			}

			my $production_sysadm_dir = catdir( rootdir(), qw(etc sysadm) );
			my $stale_file_path =
			catfile( $sysadm_target_dir, 'stale-before-run.txt' );
			my $stale_dir_path = catdir( $sysadm_target_dir, 'stale-dir' );
			my $readme_path = catfile( $sysadm_target_dir, 'README.md' );
			my $nested_file_path =
			catfile( $sysadm_target_dir, qw(roles web config.txt) );
			my $target_git_dir = catdir( $sysadm_target_dir, '.git' );
			my $stagit_dir = catdir( $harness->webroot_dir, qw(src sysadm) );
			my $stagit_git_dir = catdir( $stagit_dir, '.git' );
			my $head_path = catfile( $stagit_git_dir, 'HEAD' );
			my $info_refs_path = catfile( $stagit_git_dir, qw(info refs) );
			my $log_path = catfile( $stagit_dir, 'log.html' );
			my $index_path = catfile( $stagit_dir, 'index.html' );
			my $trace_path = $harness->fake_stagit_trace_path;

			my $result = $harness->run_post_receive(
				argv => ['-v'],
				env => {
					POST_RECEIVE_SYSADM_DIR => $sysadm_target_dir,
				},
			);
			my $run_diag =
			run_diag_with_sysadm_target( $harness, $result, $sysadm_target_dir,
			);

			is_with_diag( $result->{command}->[0],
				$harness->hook_path, 'hook ran via executable child path',
				$run_diag );
			is_with_diag( $result->{status}, 0, 'hook child status is 0',
				$run_diag );
			is_with_diag( $result->{exit_code}, 0, 'hook exit code is 0',
				$run_diag );
			is_with_diag( $result->{signal}, 0,
				'hook terminated without signal', $run_diag );

			like_with_diag(
				$sysadm_target_dir,
				qr/^\Q@{[ $harness->workspace_dir ]}\E(?:\/|\z)/,
				'sysadm target directory stays under the temp workspace',
				$run_diag,
			);
			unlike_with_diag(
				$sysadm_target_dir,
				qr/^\Q$production_sysadm_dir\E(?:\/|\z)/,
				'sysadm target directory does not point at the production /etc/sysadm path',
				$run_diag,
			);

			ok_with_diag( !-e $stale_file_path,
				'hook removed the stale sysadm target file', $run_diag );
			ok_with_diag( !-e $stale_dir_path,
				'hook removed the stale sysadm target directory', $run_diag );
			ok_with_diag(
				-f $readme_path,
				'hook deployed the top-level sysadm fixture file into the target',
				$run_diag
			);
			ok_with_diag(
				-f $nested_file_path,
				'hook deployed the nested sysadm fixture file into the target',
				$run_diag
			);
			ok_with_diag(
				!-e $target_git_dir,
				'hook did not move the cloned .git directory into the sysadm target',
				$run_diag
			);

		SKIP: {
				if ( !-f $readme_path || !-f $nested_file_path ) {
					skip 'deployed sysadm fixture files missing',
					$SYSADM_FIXTURE_CONTENT_SKIP_COUNT;
				}
				like_with_diag(
					$harness->read_file($readme_path),
					qr/^sysadm fixture README$/m,
					'deployed top-level sysadm file preserved the fixture content',
					$run_diag,
				);
				like_with_diag(
					$harness->read_file($nested_file_path),
					qr/^listen=127[.]0[.]0[.]1$/m,
					'deployed nested sysadm file preserved the fixture content',
					$run_diag,
				);
			}

			ok_with_diag(
				-d $stagit_dir,
				'shared publishing created the temp webroot src/sysadm directory',
				$run_diag
			);
			ok_with_diag(
				-f $head_path,
				'shared publishing cloned the bare repository into src/sysadm/.git/HEAD',
				$run_diag
			);
			ok_with_diag(
				-f $info_refs_path,
				'shared publishing ran git update-server-info for src/sysadm/.git/info/refs',
				$run_diag
			);
			ok_with_diag( -f $trace_path,
				'fake stagit trace was recorded for sysadm shared publishing',
				$run_diag );
			ok_with_diag( -f $log_path,
				'fake stagit generated log.html for sysadm', $run_diag );
			ok_with_diag( -f $index_path,
				'hook copied log.html to index.html for sysadm', $run_diag );

		SKIP: {
				if ( !-f $trace_path ) {
					skip 'fake stagit trace missing', $STAGIT_TRACE_SKIP_COUNT;
				}
				my $trace = $harness->parse_trace_file($trace_path);
				is_with_diag(
					$trace->{cwd},
					$stagit_dir,
					'fake stagit recorded src/sysadm as the shared publishing cwd',
					$run_diag
				);
				is_deeply(
					$trace->{argv},
					[ q{--}, $repo->{bare_repo_dir} ],
					'fake stagit recorded the expected argv for sysadm shared publishing'
				) or diag($run_diag);
			}

		SKIP: {
				if ( !-f $log_path || !-f $index_path ) {
					skip 'log.html or index.html missing',
					$LOG_INDEX_SYNC_SKIP_COUNT;
				}
				is_with_diag(
					$harness->read_file($index_path),
					$harness->read_file($log_path),
					'src/sysadm/index.html matches fake stagit log.html after the shared publishing tail',
					$run_diag,
				);
			}

			like_with_diag(
				$result->{stdout},
				qr/\QSYSADM DIRECTORY: $sysadm_target_dir\E/,
				'verbose output names the contained temp sysadm directory as active',
				$run_diag,
			);
			like_with_diag(
				$result->{stdout},
				qr/\QSTAGIT DIRECTORY: $stagit_dir\E/,
				'verbose output names the temp webroot src/sysadm directory for shared publishing',
				$run_diag,
			);
			unlike_with_diag(
				$result->{stdout},
				qr/\QSYSADM DIRECTORY: $production_sysadm_dir\E/,
				'verbose output does not report the production /etc/sysadm path as active',
				$run_diag,
			);

			done_testing();
		};

	return;
}

sub setup_dotfiles_helper_destination {
	my ($harness) = @_;

	return setup_or_return(
		'create isolated dotfiles helper-bin destination with stale helper fixtures',
		sub {
			my $bindir =
				$harness->ensure_dir(
					catdir( $harness->home_dir, qw(.local bin) ) );
			my $stale_ssg6_path = catfile( $bindir, 'ssg6' );
			my $stale_rssg_path = catfile( $bindir, 'rssg' );
			$harness->write_file(
				path => $stale_ssg6_path,
				content => "stale dotfiles ssg6 helper\n",
			);
			$harness->write_file(
				path => $stale_rssg_path,
				content => "stale dotfiles rssg helper\n",
			);
			chmod $STALE_SSG6_MODE, $stale_ssg6_path
				or die
				"Could not chmod $STALE_SSG6_MODE_TEXT $stale_ssg6_path: $OS_ERROR\n";
			chmod $STALE_RSSG_MODE, $stale_rssg_path
				or die
				"Could not chmod $STALE_RSSG_MODE_TEXT $stale_rssg_path: $OS_ERROR\n";
			return $bindir;
		},
		$harness,
	);
}

sub setup_dotfiles_repo {
	my ( $harness, $dotfiles_ssg_content, $dotfiles_rssg_content ) = @_;

	my $repo = setup_or_return(
		'create dotfiles bare repository fixture',
		sub {
			$harness->create_bare_repo(
				repo_name => 'dotfiles.git',
				file_rel => catfile(qw(.local bin ssg)),
				file_content => $dotfiles_ssg_content,
				commit_message => 'Add dotfiles ssg fixture',
			);
		},
		$harness,
	);
	if ( !$repo ) {
		return;
	}

	my $added_dotfiles_fixture = setup_or_return(
		'add dotfiles rssg fixture',
		sub {
			$harness->append_to_work_clone(
				commit_message => 'Add dotfiles rssg fixture',
				files => [
					{
						file_rel => catfile(qw(.local bin rssg)),
						content => $dotfiles_rssg_content,
					},
				],
			);
			return 1;
		},
		$harness,
	);
	if ( !$added_dotfiles_fixture ) {
		return;
	}

	return $repo;
}

sub dotfiles_caller_helper_bin {
	if ( !defined $ENV{HOME} || !length $ENV{HOME} ) {
		return;
	}

	return catdir( $ENV{HOME}, qw(.local bin) );
}

sub dotfiles_run_diag {
	my ( $harness, $result, $context ) = @_;

	my $caller_helper_bin = $context->{caller_helper_bin};
	my $caller_helper_bin_diag =
		defined $caller_helper_bin ? $caller_helper_bin : '(unset)';

	return join "\n",
		$harness->describe_run($result),
		'helper_bin_dir: ' . $context->{expected_bindir},
		'ssg6_target_path: ' . $context->{ssg6_target_path},
		'rssg_target_path: ' . $context->{rssg_target_path},
		'unexpected_ssg_path: ' . $context->{unexpected_ssg_path},
		'caller_helper_bin: ' . $caller_helper_bin_diag,
		'ssg6_mode_after_run: '
		. ( $harness->file_mode_octal( $context->{ssg6_target_path} )
			// '(missing)' ),
		'rssg_mode_after_run: '
		. ( $harness->file_mode_octal( $context->{rssg_target_path} )
			// '(missing)' );
}

sub run_dotfiles_deployment_subtest {
	subtest
		'dotfiles branch uses isolated helper replacements and preserves shared publishing tail'
		=> sub {
			my $harness = PostReceive::TestHarness->new;
			my $prereq_diag = join "\n",
			'Install the missing prerequisite on PATH before running this dotfiles branch characterization test.',
			'The test expects real git, a fake stagit shim, and an isolated HOME/.local/bin destination created inside the harness workspace.',
			$harness->workspace_diag;

			my $assets = setup_or_return( 'seed shared stagit assets',
				sub { $harness->seed_stagit_assets }, $harness, );
			if ( !$assets ) {
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

			my $expected_bindir = setup_dotfiles_helper_destination($harness);
			if ( !$expected_bindir ) {
				return;
			}

			my $ssg6_target_path = catfile( $expected_bindir, 'ssg6' );
			my $rssg_target_path = catfile( $expected_bindir, 'rssg' );
			my $unexpected_ssg_path = catfile( $expected_bindir, 'ssg' );
			my $dotfiles_ssg_content = "dotfiles fixture ssg source\n";
			my $dotfiles_rssg_content = "dotfiles fixture rssg source\n";

			my $repo = setup_dotfiles_repo( $harness, $dotfiles_ssg_content,
				$dotfiles_rssg_content, );
			if ( !$repo ) {
				return;
			}

			my $caller_helper_bin = dotfiles_caller_helper_bin();
			my $stagit_dir = catdir( $harness->webroot_dir, qw(src dotfiles) );
			my $stagit_git_dir = catdir( $stagit_dir, '.git' );
			my $head_path = catfile( $stagit_git_dir, 'HEAD' );
			my $info_refs_path = catfile( $stagit_git_dir, qw(info refs) );
			my $log_path = catfile( $stagit_dir, 'log.html' );
			my $index_path = catfile( $stagit_dir, 'index.html' );
			my $trace_path = $harness->fake_stagit_trace_path;

			my $result = $harness->run_post_receive( argv => ['-v'] );
			my $run_diag = dotfiles_run_diag(
				$harness, $result,
				{
					expected_bindir => $expected_bindir,
					ssg6_target_path => $ssg6_target_path,
					rssg_target_path => $rssg_target_path,
					unexpected_ssg_path => $unexpected_ssg_path,
					caller_helper_bin => $caller_helper_bin,
				},
			);

			is_with_diag( $result->{command}->[0],
				$harness->hook_path, 'hook ran via executable child path',
				$run_diag );
			is_with_diag( $result->{status}, 0, 'hook child status is 0',
				$run_diag );
			is_with_diag( $result->{exit_code}, 0, 'hook exit code is 0',
				$run_diag );
			is_with_diag( $result->{signal}, 0,
				'hook terminated without signal', $run_diag );

			like_with_diag(
				$expected_bindir,
				qr/^\Q@{[ $harness->home_dir ]}\E(?:\/|\z)/,
				'isolated helper bin stays under the temp HOME directory',
				$run_diag,
			);
			like_with_diag(
				$stagit_dir,
				qr/^\Q@{[ $harness->webroot_dir ]}\E(?:\/|\z)/,
				'shared publishing output stays under the temp webroot',
				$run_diag,
			);

			if ( defined $caller_helper_bin ) {
				unlike_with_diag(
					$expected_bindir,
					qr/^\Q$caller_helper_bin\E(?:\/|\z)/,
					'isolated helper bin does not point into the caller HOME helper-bin path',
					$run_diag,
				);
			}
			else {
				pass(
				'caller HOME is unavailable so no real helper-bin path can leak into the isolated helper directory'
				);
			}

			ok_with_diag( -f $ssg6_target_path,
				'hook left an ssg6 helper in the isolated HOME helper bin',
				$run_diag );
			ok_with_diag( -f $rssg_target_path,
				'hook left an rssg helper in the isolated HOME helper bin',
				$run_diag );
			ok_with_diag(
				!-e $unexpected_ssg_path,
				'hook did not leave a same-name ssg helper in the isolated HOME helper bin',
				$run_diag
			);

		SKIP: {
				if ( !-f $ssg6_target_path || !-f $rssg_target_path ) {
					skip 'isolated dotfiles helper replacements missing',
					$DOTFILES_HELPER_REPLACEMENT_SKIP_COUNT;
				}
				is_with_diag(
					$harness->read_file($ssg6_target_path),
					$dotfiles_ssg_content,
					'ssg6 content now comes from fixture .local/bin/ssg',
					$run_diag,
				);
				is_with_diag(
					$harness->read_file($rssg_target_path),
					$dotfiles_rssg_content,
					'rssg content now comes from fixture .local/bin/rssg',
					$run_diag,
				);
				is_with_diag(
					$harness->file_mode_octal($ssg6_target_path), '0700',
					'hook reset the ssg6 helper mode to 0700', $run_diag,
				);
				is_with_diag(
					$harness->file_mode_octal($rssg_target_path), '0700',
					'hook reset the rssg helper mode to 0700', $run_diag,
				);
			}

			ok_with_diag(
				-d $stagit_dir,
				'shared publishing created the temp webroot src/dotfiles directory',
				$run_diag
			);
			ok_with_diag(
				-f $head_path,
				'shared publishing cloned the bare repository into src/dotfiles/.git/HEAD',
				$run_diag
			);
			ok_with_diag(
				-f $info_refs_path,
				'shared publishing ran git update-server-info for src/dotfiles/.git/info/refs',
				$run_diag
			);
			ok_with_diag(
				-f $trace_path,
				'fake stagit trace was recorded for dotfiles shared publishing',
				$run_diag
			);
			ok_with_diag( -f $log_path,
				'fake stagit generated log.html for dotfiles', $run_diag );
			ok_with_diag( -f $index_path,
				'hook copied log.html to index.html for dotfiles', $run_diag );

		SKIP: {
				if ( !-f $trace_path ) {
					skip 'fake stagit trace missing', $STAGIT_TRACE_SKIP_COUNT;
				}
				my $trace = $harness->parse_trace_file($trace_path);
				is_with_diag(
					$trace->{cwd},
					$stagit_dir,
					'fake stagit recorded src/dotfiles as the shared publishing cwd',
					$run_diag
				);
				is_deeply(
					$trace->{argv},
					[ q{--}, $repo->{bare_repo_dir} ],
					'fake stagit recorded the expected argv for dotfiles shared publishing'
				) or diag($run_diag);
			}

		SKIP: {
				if ( !-f $log_path || !-f $index_path ) {
					skip 'log.html or index.html missing',
					$LOG_INDEX_SYNC_SKIP_COUNT;
				}
				is_with_diag(
					$harness->read_file($index_path),
					$harness->read_file($log_path),
					'src/dotfiles/index.html matches fake stagit log.html after the shared publishing tail',
					$run_diag
				);
			}

			like_with_diag(
				$result->{stdout},
				qr/\QBINARY DIRECTORY: $expected_bindir\E/,
				'verbose output names the isolated HOME helper-bin path for dotfiles',
				$run_diag,
			);
			like_with_diag(
				$result->{stdout},
				qr/\QSSG LOCATION: $ssg6_target_path\E/,
				'verbose output records the isolated ssg6 destination path',
				$run_diag,
			);
			like_with_diag(
				$result->{stdout},
				qr/\QRSSG LOCATION: $rssg_target_path\E/,
				'verbose output records the isolated rssg destination path',
				$run_diag,
			);
			like_with_diag(
				$result->{stdout},
				qr/\QSTAGIT DIRECTORY: $stagit_dir\E/,
				'verbose output names the temp webroot src/dotfiles directory for shared publishing',
				$run_diag,
			);

			if ( defined $caller_helper_bin ) {
				unlike_with_diag(
					$result->{stdout},
					qr/\Q$caller_helper_bin\E/,
					'verbose output does not report the caller HOME helper-bin path as active',
					$run_diag,
				);
			}
			else {
				pass(
				'caller HOME is unavailable so there is no caller helper-bin path for verbose output to report'
				);
			}

			done_testing();
		};

	return;
}

run_append_validation_subtest();
run_sysadm_deployment_subtest();
run_dotfiles_deployment_subtest();

done_testing();
