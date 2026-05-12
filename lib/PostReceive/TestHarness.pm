package PostReceive::TestHarness;

use strict;
use warnings;

use Carp qw(croak);
use Cwd qw(abs_path);
use File::Basename qw(dirname);
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);

sub new {
	my ( $class, %args ) = @_;

	my $repo_root = $args{repo_root} // _resolve_repo_root();
	croak "Resolved repository root does not exist: $repo_root\n"
		unless -d $repo_root;

	my $hook_path = File::Spec->catfile( $repo_root, 'bin', 'post-receive' );
	croak "Resolved hook path does not exist: $hook_path\n"
		unless -f $hook_path;

	my $workspace_dir = tempdir(
		'post-receive-harness-XXXXXXXX',
		TMPDIR  => 1,
		CLEANUP => exists $args{cleanup} ? $args{cleanup} : 1,
	);

	my $home_dir = _ensure_dir( File::Spec->catdir( $workspace_dir, 'home' ) );
	my $webroot_dir = _ensure_dir( File::Spec->catdir( $workspace_dir, 'webroot' ) );
	my $fake_command_dir =
		_ensure_dir( File::Spec->catdir( $workspace_dir, 'fake-bin' ) );
	my $repo_fixture_root =
		_ensure_dir( File::Spec->catdir( $workspace_dir, 'repos' ) );
	my $capture_dir = _ensure_dir( File::Spec->catdir( $workspace_dir, 'captures' ) );

	my $self = bless {
		repo_root              => $repo_root,
		hook_path              => $hook_path,
		workspace_dir          => $workspace_dir,
		home_dir               => $home_dir,
		webroot_dir            => $webroot_dir,
		fake_command_dir       => $fake_command_dir,
		repo_fixture_root      => $repo_fixture_root,
		capture_dir            => $capture_dir,
		child_stdout_path      => File::Spec->catfile( $workspace_dir, 'hook.stdout' ),
		child_stderr_path      => File::Spec->catfile( $workspace_dir, 'hook.stderr' ),
		fake_stagit_trace_path => File::Spec->catfile(
			$workspace_dir,
			'fake-stagit.trace'
		),
		path            => _build_path($fake_command_dir),
		command_counter => 0,
		command_results => [],
	}, $class;

	return $self;
}

sub repo_root { return $_[0]->{repo_root}; }
sub hook_path { return $_[0]->{hook_path}; }
sub workspace_dir { return $_[0]->{workspace_dir}; }
sub home_dir { return $_[0]->{home_dir}; }
sub webroot_dir { return $_[0]->{webroot_dir}; }
sub fake_command_dir { return $_[0]->{fake_command_dir}; }
sub repo_fixture_root { return $_[0]->{repo_fixture_root}; }
sub capture_dir { return $_[0]->{capture_dir}; }
sub child_stdout_path { return $_[0]->{child_stdout_path}; }
sub child_stderr_path { return $_[0]->{child_stderr_path}; }
sub fake_stagit_trace_path { return $_[0]->{fake_stagit_trace_path}; }
sub fake_stagit_path { return $_[0]->{fake_stagit_path}; }
sub stagit_asset_dir { return $_[0]->{stagit_asset_dir}; }
sub bare_repo_dir { return $_[0]->{bare_repo_dir}; }
sub work_clone_dir { return $_[0]->{work_clone_dir}; }
sub path { return $_[0]->{path}; }
sub command_results { return $_[0]->{command_results}; }
sub last_hook_result { return $_[0]->{last_hook_result}; }

sub describe_workspace {
	my ($self) = @_;

	return join(
		"\n",
		'workspace_dir: ' . $self->{workspace_dir},
		'home_dir: ' . $self->{home_dir},
		'webroot_dir: ' . $self->{webroot_dir},
		'fake_command_dir: ' . $self->{fake_command_dir},
		'repo_fixture_root: ' . $self->{repo_fixture_root},
		'PATH: ' . $self->{path},
	);
}

sub workspace_diag {
	my ($self) = @_;
	return $self->describe_workspace;
}

sub ensure_dir {
	my ( $self, $path ) = @_;

	croak "ensure_dir requires a path\n"
		unless defined $path && length $path;

	my $absolute_path = _absolute_path( $path, $self->{workspace_dir} );
	return _ensure_dir($absolute_path);
}

sub write_file {
	my ( $self, %args ) = @_;

	my $path = $args{path}
		// croak "write_file requires a path\n";
	my $absolute_path = _absolute_path( $path, $self->{workspace_dir} );

	_write_file(
		path    => $absolute_path,
		content => defined $args{content} ? $args{content} : q{},
		binary  => $args{binary},
	);

	return $absolute_path;
}

sub executable_on_path {
	my ( $self, $name, %args ) = @_;

	croak "executable_on_path requires a name\n"
		unless defined $name && length $name;

	my $path = exists $args{path} ? $args{path} : $self->{path};
	return unless defined $path && length $path;

	for my $dir ( split /:/, $path ) {
		next unless defined $dir && length $dir;
		my $candidate = File::Spec->catfile(
			_absolute_path( $dir, $self->{workspace_dir} ),
			$name,
		);
		return $candidate if -f $candidate && -x $candidate;
	}

	return;
}

sub executable_in_dir {
	my ( $self, $dir, $name ) = @_;

	croak "executable_in_dir requires a directory\n"
		unless defined $dir && length $dir;
	croak "executable_in_dir requires a name\n"
		unless defined $name && length $name;

	my $candidate = File::Spec->catfile(
		_absolute_path( $dir, $self->{workspace_dir} ),
		$name,
	);
	return $candidate if -f $candidate && -x $candidate;

	return;
}

sub parse_trace {
	my ( $self, $trace_text ) = @_;

	croak "parse_trace requires trace text\n"
		unless defined $trace_text;

	my %trace = ( argv => [] );
	for my $line ( split /\n/, $trace_text ) {
		if ( $line =~ /^argv\[(\d+)\]=(.*)\z/ ) {
			$trace{argv}->[$1] = $2;
			next;
		}
		if ( $line =~ /^([A-Za-z0-9_.-]+)=(.*)\z/ ) {
			$trace{$1} = $2;
		}
	}

	return \%trace;
}

sub parse_trace_file {
	my ( $self, $path ) = @_;

	croak "parse_trace_file requires a path\n"
		unless defined $path && length $path;

	my $absolute_path = _absolute_path( $path, $self->{workspace_dir} );
	return $self->parse_trace( _slurp_file($absolute_path) );
}

sub file_mode_octal {
	my ( $self, $path ) = @_;

	croak "file_mode_octal requires a path\n"
		unless defined $path && length $path;

	my $absolute_path = _absolute_path( $path, $self->{workspace_dir} );
	return unless -e $absolute_path;

	my $mode = ( stat $absolute_path )[2];
	return unless defined $mode;

	return sprintf '%04o', $mode & 07777;
}

sub seed_stagit_assets {
	my ( $self, %args ) = @_;

	my $asset_dir = _ensure_dir( File::Spec->catdir( $self->{webroot_dir}, 'stagit' ) );
	my $style_css_path = File::Spec->catfile( $asset_dir, 'style.css' );
	my $logo_png_path = File::Spec->catfile( $asset_dir, 'logo.png' );
	my $favicon_png_path = File::Spec->catfile( $asset_dir, 'favicon.png' );
	my $png_stub = "\x89PNG\x0D\x0A\x1A\x0AFAKEPNG\n";

	_write_file(
		path    => $style_css_path,
		content => $args{style_css}
			// "/* fake stagit stylesheet */\nbody { background: #fff; }\n",
	);
	_write_file(
		path    => $logo_png_path,
		content => $args{logo_png} // $png_stub,
		binary  => 1,
	);
	_write_file(
		path    => $favicon_png_path,
		content => $args{favicon_png} // $png_stub,
		binary  => 1,
	);

	$self->{stagit_asset_dir} = $asset_dir;

	return {
		asset_dir        => $asset_dir,
		style_css_path   => $style_css_path,
		logo_png_path    => $logo_png_path,
		favicon_png_path => $favicon_png_path,
	};
}

sub install_fake_stagit {
	my ( $self, %args ) = @_;

	my $trace_path = _absolute_path(
		$args{trace_path} // $self->{fake_stagit_trace_path},
		$self->{workspace_dir}
	);
	_ensure_dir( dirname($trace_path) );

	my $fake_stagit_path =
		File::Spec->catfile( $self->{fake_command_dir}, 'stagit' );

	my $trace_literal = _perl_single_quote($trace_path);

	my $script = <<"FAKE_STAGIT";
#!/usr/bin/env perl
use strict;
use warnings;
use Cwd qw(getcwd);

my \$trace_path = $trace_literal;

open my \$trace_fh, '>', \$trace_path
	or die "Could not open \$trace_path for writing: \$!\\n";
print {\$trace_fh} "cwd=", getcwd(), "\\n";
for my \$index ( 0 .. \$#ARGV ) {
	print {\$trace_fh} "argv[\$index]=", \$ARGV[\$index], "\\n";
}
close \$trace_fh
	or die "Could not close \$trace_path: \$!\\n";

open my \$log_fh, '>', 'log.html'
	or die "Could not open log.html for writing: \$!\\n";
my \$repo = \@ARGV ? \$ARGV[-1] : '';
print {\$log_fh} "<!doctype html>\\n";
print {\$log_fh} "<title>fake stagit</title>\\n";
print {\$log_fh} "<p>\$repo</p>\\n";
close \$log_fh
	or die "Could not close log.html: \$!\\n";
FAKE_STAGIT

	_write_file(
		path    => $fake_stagit_path,
		content => $script,
	);
	chmod 0700, $fake_stagit_path
		or croak "Could not chmod 0700 $fake_stagit_path: $!\n";

	$self->{fake_stagit_path} = $fake_stagit_path;
	$self->{fake_stagit_trace_path} = $trace_path;

	return {
		fake_stagit_path => $fake_stagit_path,
		trace_path       => $trace_path,
	};
}

sub create_bare_repo {
	my ( $self, %args ) = @_;

	my $repo_name = $args{repo_name} // 'learning_perl_exercises.git';
	my $work_name = $repo_name;
	$work_name =~ s/\.git\z//;

	my $bare_repo_dir =
		File::Spec->catdir( $self->{repo_fixture_root}, $repo_name );
	my $work_clone_dir =
		File::Spec->catdir( $self->{repo_fixture_root}, $work_name . '-work' );
	my $file_rel = $args{file_rel} // 'README.md';
	my $file_path = File::Spec->catfile(
		$work_clone_dir,
		File::Spec->splitdir($file_rel)
	);

	$self->_run_checked_command(
		label   => 'git-init-bare',
		cwd     => $self->{workspace_dir},
		command => [ qw(git init --bare --), $bare_repo_dir ],
		env     => $self->_base_env,
	);

	$self->_run_checked_command(
		label   => 'git-clone-bare',
		cwd     => $self->{workspace_dir},
		command => [ qw(git clone --), $bare_repo_dir, $work_clone_dir ],
		env     => $self->_base_env,
	);

	_ensure_dir( dirname($file_path) );
	_write_file(
		path    => $file_path,
		content => $args{file_content} // "Fixture content for $repo_name\n",
	);

	$self->_run_checked_command(
		label   => 'git-config-user-name',
		cwd     => $self->{workspace_dir},
		command => [
			qw(git -C), $work_clone_dir,
			qw(config user.name),
			$args{user_name} // 'PostReceive Harness',
		],
		env     => $self->_base_env,
	);

	$self->_run_checked_command(
		label   => 'git-config-user-email',
		cwd     => $self->{workspace_dir},
		command => [
			qw(git -C), $work_clone_dir,
			qw(config user.email),
			$args{user_email} // 'post-receive-harness@example.test',
		],
		env     => $self->_base_env,
	);

	$self->_run_checked_command(
		label   => 'git-add-fixture',
		cwd     => $self->{workspace_dir},
		command => [ qw(git -C), $work_clone_dir, qw(add --), $file_rel ],
		env     => $self->_base_env,
	);

	$self->_run_checked_command(
		label   => 'git-commit-fixture',
		cwd     => $self->{workspace_dir},
		command => [
			qw(git -C), $work_clone_dir,
			qw(commit -m),
			$args{commit_message} // 'Initial fixture commit',
		],
		env     => $self->_base_env,
	);

	$self->_run_checked_command(
		label   => 'git-push-fixture',
		cwd     => $self->{workspace_dir},
		command => [ qw(git -C), $work_clone_dir, qw(push origin HEAD) ],
		env     => $self->_base_env,
	);

	$self->{bare_repo_dir} = $bare_repo_dir;
	$self->{work_clone_dir} = $work_clone_dir;

	return {
		repo_name      => $repo_name,
		bare_repo_dir  => $bare_repo_dir,
		work_clone_dir => $work_clone_dir,
		file_rel       => $file_rel,
		file_path      => $file_path,
	};
}

sub append_to_work_clone {
	my ( $self, %args ) = @_;

	my $work_clone_dir = $args{work_clone_dir}
		// $self->{work_clone_dir}
		// croak "append_to_work_clone requires work_clone_dir or a prior create_bare_repo call\n";
	my $absolute_work_clone_dir = _absolute_path(
		$work_clone_dir,
		$self->{workspace_dir}
	);
	croak "append_to_work_clone work_clone_dir does not exist: $absolute_work_clone_dir\n"
		unless -d $absolute_work_clone_dir;

	my $files = $args{files};
	croak "append_to_work_clone requires a non-empty files array reference\n"
		unless ref $files eq 'ARRAY' && @{$files};

	my @git_add;
	for my $file ( @{$files} ) {
		croak "append_to_work_clone expects each file entry as a hash reference\n"
			unless ref $file eq 'HASH';

		my $file_rel = $file->{file_rel};
		croak "append_to_work_clone file entry is missing file_rel\n"
			unless defined $file_rel && length $file_rel;
		croak "append_to_work_clone file_rel must be relative: $file_rel\n"
			if File::Spec->file_name_is_absolute($file_rel);

		my @file_parts = File::Spec->splitdir($file_rel);
		croak "append_to_work_clone file_rel must stay within the work clone: $file_rel\n"
			if grep { defined $_ && $_ eq File::Spec->updir } @file_parts;

		my $file_path = File::Spec->catfile(
			$absolute_work_clone_dir,
			@file_parts,
		);
		$self->write_file(
			path    => $file_path,
			content => defined $file->{content} ? $file->{content} : q{},
			binary  => $file->{binary},
		);
		push @git_add, $file_rel;
	}

	my $commit_message = $args{commit_message} // 'Append fixture files';
	my $env = $self->_base_env;

	$self->_run_checked_command(
		label   => 'git-add-appended-fixture',
		cwd     => $absolute_work_clone_dir,
		command => [ qw(git add --), @git_add ],
		env     => $env,
	);
	$self->_run_checked_command(
		label   => 'git-commit-appended-fixture',
		cwd     => $absolute_work_clone_dir,
		command => [ qw(git commit -m), $commit_message ],
		env     => $env,
	);
	$self->_run_checked_command(
		label   => 'git-push-appended-fixture',
		cwd     => $absolute_work_clone_dir,
		command => [ qw(git push origin HEAD) ],
		env     => $env,
	);

	$self->{work_clone_dir} = $absolute_work_clone_dir;

	return {
		work_clone_dir  => $absolute_work_clone_dir,
		files           => [ @git_add ],
		commit_message  => $commit_message,
	};
}

sub run_post_receive {
	my ( $self, %args ) = @_;

	my $cwd = $args{cwd}
		// $self->{bare_repo_dir}
		// croak "run_post_receive requires an explicit cwd or a prior create_bare_repo call\n";

	my $argv = $args{argv} // [];
	croak "run_post_receive expects argv as an array reference\n"
		unless ref $argv eq 'ARRAY';

	my $env_arg = $args{env} // {};
	croak "run_post_receive expects env as a hash reference\n"
		unless ref $env_arg eq 'HASH';

	my $stdout_path = _absolute_path(
		$args{stdout_path} // $self->{child_stdout_path},
		$self->{workspace_dir}
	);
	my $stderr_path = _absolute_path(
		$args{stderr_path} // $self->{child_stderr_path},
		$self->{workspace_dir}
	);
	$self->{child_stdout_path} = $stdout_path;
	$self->{child_stderr_path} = $stderr_path;

	unlink $stdout_path if -e $stdout_path;
	unlink $stderr_path if -e $stderr_path;
	unlink $self->{fake_stagit_trace_path}
		if defined $self->{fake_stagit_trace_path}
		&& -e $self->{fake_stagit_trace_path};

	my %extra_env = %{$env_arg};
	if (
		( !exists $args{with_webroot_override} || $args{with_webroot_override} )
		&& !exists $extra_env{POST_RECEIVE_WEB_SERVER_DIR}
	) {
		$extra_env{POST_RECEIVE_WEB_SERVER_DIR} = $self->{webroot_dir};
	}

	my %env = (
		%{ $self->_base_env },
		%extra_env,
	);

	my $result = $self->_run_command(
		label       => 'post-receive',
		cwd         => $cwd,
		command     => [ $self->{hook_path}, @{$argv} ],
		env         => \%env,
		stdout_path => $stdout_path,
		stderr_path => $stderr_path,
	);

	$self->{last_hook_result} = $result;

	return $result;
}

sub describe_run {
	my ( $self, $result ) = @_;

	croak "describe_run requires a result hash reference\n"
		unless ref $result eq 'HASH';

	my @lines = (
		"workspace_dir: $self->{workspace_dir}",
		"home_dir: $self->{home_dir}",
		"webroot_dir: $self->{webroot_dir}",
		"fake_command_dir: $self->{fake_command_dir}",
		"repo_fixture_root: $self->{repo_fixture_root}",
		"bare_repo_dir: " . ( $self->{bare_repo_dir} // '(unset)' ),
		"work_clone_dir: " . ( $self->{work_clone_dir} // '(unset)' ),
		"hook_path: $self->{hook_path}",
		"command: $result->{command_string}",
		"cwd: $result->{cwd}",
		"status: $result->{status}",
		"exit_code: $result->{exit_code}",
		"signal: $result->{signal}",
		"stdout_path: $result->{stdout_path}",
		"stderr_path: $result->{stderr_path}",
		"stdout:",
		length $result->{stdout} ? $result->{stdout} : '(empty)',
		"stderr:",
		length $result->{stderr} ? $result->{stderr} : '(empty)',
	);

	if ( defined $self->{fake_stagit_trace_path} ) {
		push @lines,
			"fake_stagit_trace_path: $self->{fake_stagit_trace_path}";
		if ( -e $self->{fake_stagit_trace_path} ) {
			push @lines,
				"fake_stagit_trace:",
				$self->read_file( $self->{fake_stagit_trace_path} );
		}
		else {
			push @lines,
				"fake_stagit_trace:",
				'(missing)';
		}
	}

	return join "\n", @lines;
}

sub read_file {
	my ( $self, $path ) = @_;

	return _slurp_file(
		_absolute_path( $path, $self->{workspace_dir} )
	);
}

sub _base_env {
	my ($self) = @_;

	return {
		HOME => $self->{home_dir},
		PATH => $self->{path},
	};
}

sub _run_checked_command {
	my ( $self, %args ) = @_;

	my $label = $args{label} // 'command';
	my $result = $self->_run_command(%args);

	return $result if $result->{status} == 0;

	croak _result_failure_message( $label, $result );
}

sub _run_command {
	my ( $self, %args ) = @_;

	my $command = $args{command};
	croak "_run_command requires a non-empty command array reference\n"
		unless ref $command eq 'ARRAY' && @{$command};

	my $label = $args{label} // $command->[0];
	my $cwd = _absolute_path(
		$args{cwd} // $self->{workspace_dir},
		$self->{workspace_dir}
	);

	croak "Command cwd does not exist: $cwd\n"
		unless -d $cwd;

	my $env = $args{env} // {};
	croak "_run_command expects env as a hash reference\n"
		unless ref $env eq 'HASH';

	my $captures = $args{stdout_path} || $args{stderr_path}
		? {
			stdout => _absolute_path(
				$args{stdout_path} // $self->{child_stdout_path},
				$self->{workspace_dir}
			),
			stderr => _absolute_path(
				$args{stderr_path} // $self->{child_stderr_path},
				$self->{workspace_dir}
			),
		}
		: $self->_next_capture_paths($label);

	_ensure_dir( dirname( $captures->{stdout} ) );
	_ensure_dir( dirname( $captures->{stderr} ) );

	unlink $captures->{stdout} if -e $captures->{stdout};
	unlink $captures->{stderr} if -e $captures->{stderr};

	my $pid = fork();
	croak "Could not fork for " . _format_command($command) . ": $!\n"
		unless defined $pid;

	if ( $pid == 0 ) {
		open STDIN, '<', File::Spec->devnull()
			or exit 126;
		open STDOUT, '>', $captures->{stdout}
			or exit 126;
		open STDERR, '>', $captures->{stderr}
			or exit 126;

		chdir $cwd or do {
			print STDERR "Could not chdir to $cwd: $!\\n";
			exit 126;
		};

		local %ENV = ( %ENV, %{$env} );

		exec { $command->[0] } @{$command}
			or do {
				print STDERR "Could not exec " . _format_command($command) . ": $!\\n";
				exit 127;
			};
	}

	waitpid $pid, 0;
	my $status = $?;

	my $result = {
		label          => $label,
		command        => [ @{$command} ],
		command_string => _format_command($command),
		cwd            => $cwd,
		stdout_path    => $captures->{stdout},
		stderr_path    => $captures->{stderr},
		status         => $status,
		exit_code      => $status >> 8,
		signal         => $status & 127,
		dumped_core    => ( $status & 128 ) ? 1 : 0,
		stdout         => _read_file_if_exists( $captures->{stdout} ),
		stderr         => _read_file_if_exists( $captures->{stderr} ),
		env            => { %{$env} },
	};

	push @{ $self->{command_results} }, $result;

	return $result;
}

sub _next_capture_paths {
	my ( $self, $label ) = @_;

	$self->{command_counter}++;
	my $safe_label = $label // 'command';
	$safe_label =~ s/[^A-Za-z0-9._-]+/-/g;
	$safe_label =~ s/\A-+//;
	$safe_label =~ s/-+\z//;
	$safe_label ||= 'command';

	my $prefix = sprintf '%02d-%s', $self->{command_counter}, $safe_label;

	return {
		stdout => File::Spec->catfile(
			$self->{capture_dir},
			"$prefix.stdout"
		),
		stderr => File::Spec->catfile(
			$self->{capture_dir},
			"$prefix.stderr"
		),
	};
}

sub _resolve_repo_root {
	my $module_path = abs_path(__FILE__)
		or croak "Could not resolve module path for " . __FILE__ . "\n";

	my $repo_root = abs_path(
		File::Spec->catdir(
			dirname($module_path),
			File::Spec->updir,
			File::Spec->updir,
		)
	) or croak "Could not resolve repository root relative to $module_path\n";

	return $repo_root;
}

sub _ensure_dir {
	my ($path) = @_;

	return $path if -d $path;

	make_path($path)
		or croak "Could not create directory $path: $!\n";

	return $path;
}

sub _absolute_path {
	my ( $path, $base ) = @_;

	return $path if File::Spec->file_name_is_absolute($path);

	return File::Spec->rel2abs( $path, $base );
}

sub _build_path {
	my ($fake_command_dir) = @_;

	return join q{:},
		grep { defined && length }
		$fake_command_dir,
		$ENV{PATH};
}

sub _perl_single_quote {
	my ($text) = @_;

	$text =~ s{\\}{\\\\}g;
	$text =~ s{'}{\\'}g;

	return "'$text'";
}

sub _write_file {
	my (%args) = @_;

	my $path = $args{path}
		// croak "_write_file requires a path\n";
	my $content = defined $args{content} ? $args{content} : q{};

	_ensure_dir( dirname($path) );

	open my $fh, '>', $path
		or croak "Could not open $path for writing: $!\n";
	if ( $args{binary} ) {
		binmode $fh or croak "Could not enable binmode for $path: $!\n";
	}
	print {$fh} $content
		or croak "Could not write to $path: $!\n";
	close $fh
		or croak "Could not close $path: $!\n";
}

sub _slurp_file {
	my ($path) = @_;

	open my $fh, '<', $path
		or croak "Could not open $path for reading: $!\n";
	binmode $fh or croak "Could not enable binmode for $path: $!\n";
	local $/;
	my $content = <$fh>;
	close $fh
		or croak "Could not close $path: $!\n";

	return defined $content ? $content : q{};
}

sub _read_file_if_exists {
	my ($path) = @_;

	return q{} unless defined $path && -e $path;

	return _slurp_file($path);
}

sub _format_command {
	my ($command) = @_;

	return join q{ }, map { _shell_quote($_) } @{$command};
}

sub _shell_quote {
	my ($text) = @_;

	$text = q{} unless defined $text;
	return "''" if $text eq q{};

	if ( $text =~ /\A[-A-Za-z0-9_.,:\/=]+\z/ ) {
		return $text;
	}

	$text =~ s/'/'"'"'/g;
	return "'$text'";
}

sub _result_failure_message {
	my ( $label, $result ) = @_;

	return join(
		"\n",
		"$label failed",
		"command: $result->{command_string}",
		"cwd: $result->{cwd}",
		"status: $result->{status}",
		"exit_code: $result->{exit_code}",
		"signal: $result->{signal}",
		"stdout_path: $result->{stdout_path}",
		"stderr_path: $result->{stderr_path}",
		"stdout:",
		length $result->{stdout} ? $result->{stdout} : '(empty)',
		"stderr:",
		length $result->{stderr} ? $result->{stderr} : '(empty)',
	) . "\n";
}

1;
