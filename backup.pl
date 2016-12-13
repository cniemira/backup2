#!/usr/bin/perl

use Cwd;
use Date::Format;
use Date::Parse;
use Digest::MD5;
use File::Find;
use FileHandle;
use File::Spec;
use Getopt::Long;
use Pod::Usage;
use SVN::Core;
use SVN::Repos;
use SVN::Fs;
use Text::Diff;

use strict;
use warnings;
use vars qw/%arc @files %opt/;

&init;
&main;


##########
sub err {
##########
	print STDERR shift() . "\n";
	my $x = shift || return 1;
	exit $x;
}


##########
sub say {
##########
	my $msg = shift;
	my $cutoff = shift || 1;
	print STDOUT $msg . "\n" if $opt{'verbosity'} >= $cutoff;
}


###############################################################################


################
sub doArchive {
################
	my $tran = $arc{'fs'}->begin_txn($arc{'rev'});
	my $root = $tran->root;
	
	my $c = 0;
	
	foreach (@files) {
		# make sure I can open the source file
		my $input = FileHandle->new("< $_") || (err("Could not open $_") && next);
		
		# is the file already there?
		if ($arc{'rev_root'}->check_path($_) != $SVN::Node::none) {
			# determine if the file has changed
			my $sum = Digest::MD5->new->addfile($input)->hexdigest;
			my $arcsum = $arc{'rev_root'}->file_md5_checksum($_);

			if ($sum eq $arcsum) {
				say('I: ' . $_, 2);
				$input->close;
				next;
			}
			
			# be sure to rewind the FH
			$input->seek(0, 0);
		
			# I should probably do a diff, and only apply the changes
			say('U: ' . $_);

		# check the directories, one by one, and make 'em if needed
		} else {
			my @pathTo = File::Spec->splitdir($_);
			my $file = pop @pathTo;
			my $path = '';

			while (@pathTo) {
				$path = File::Spec::Unix->join($path, shift @pathTo);
				if ($arc{'rev_root'}->check_path($path) == $SVN::Node::none) {
					say('A: ' . $path);
					$root->make_dir($path, SVN::Pool->new);
			    }
			}		

			say('A: ' . $_);
			$root->make_file($_);
		}

		# import the file
		my $stream = $root->apply_text($_, undef);
		$root->change_node_prop($_, 'backup:sourceabspath', $_);

		my $buffer;
		# prolly not the best way to do this...
		syswrite($stream, $buffer) while sysread($input, $buffer, 1024);

		$input->close;
		$c++;
	}
	
	if ($c > 0) {
		my @rev = $tran->commit;
		$arc{'fs'}->change_rev_prop($rev[1], 'svn:log', $opt{'comment'}) if $opt{'comment'};

		say('V: ' . $rev[1], 2);

	} else {
		# if there were no changes, say so!
		err('No changes.', 1);
	}

}


###############
sub doDelete {
###############
	my $tran = $arc{'fs'}->begin_txn($arc{'rev'});
	my $root = $tran->root;
	
	my $c = 0;
	
	foreach (@files) {
		if ($arc{'rev_root'}->check_path($_) != $SVN::Node::none) {
			$root->delete($_);
			say('D: ' . $_);
			$c++;
		}
	}

	if ($c > 0) {
		my @rev = $tran->commit;
		$arc{'fs'}->change_rev_prop($rev[1], 'svn:log', $opt{'comment'}) if $opt{'comment'};

		say('V: ' . $rev[1], 2);
	} else {
		err('No changes.', 1);
	}
}


#############
sub doDiff {
#############
	my $rev = $opt{'versionNumber'} || $arc{'rev'};
	my $root = $arc{'fs'}->revision_root($rev);
	say("Opened revision " . $rev, 3);

	foreach (@files) {
		if ($root->check_path($_) != $SVN::Node::none) {
			say('F: ' . $_);
			my $stream = $root->file_contents($_);
			my $txt; read($stream, $txt, $root->file_length($_));
			close $stream;
			say(diff(\$txt, $_));

		} else {
			say('N: ' . $_, 2);
		}
	}
}


#############
sub doList {
#############
	my $c = 0;
	my %macro;
	my $template = $opt{'format'} || $opt{'listFormat'};

	# there's really GOT to be a better way to do this whole subroutine...	
	$macro{'%V'} = $arc{'rev'};
	my (%cache, %list, %note);

	# loop through each revision (backwards)
	while ($macro{'%V'} >= 0) {
		my $root = $arc{'fs'}->revision_root($macro{'%V'});
		say("Searching revision " . $macro{'%V'}, 3);

		# cache the date and comments
		$macro{'%F'} = $arc{'fs'}->revision_prop($macro{'%V'}, 'svn:log') || '';
		$macro{'%K'} = $opt{'archiveDirectory'};
		$macro{'%s'} = str2time($arc{'fs'}->revision_prop($macro{'%V'}, 'svn:date'));
		$macro{'%v'} = sprintf(' %7s', $arc{'fs'}->revision_prop($macro{'%V'}, 'svn:author') || 'unknown');

		$note{$macro{'%V'}} = macroReplace($template, \%macro);

		# now loop through each file we're looking for, and see if the previous
		# (higher numbered) revision had a different version
		foreach (@files) {
			my $arcsum = $root->check_path($_) != $SVN::Node::none ? $root->file_md5_checksum($_) : \0;
			push @{$list{$_}}, $macro{'%V'} + 1 if ($cache{$_} && $cache{$_} ne $arcsum);
			$cache{$_} = $arcsum;
		} 

		$macro{'%V'}--;
	}

	# if we found differences, enumerate them here
	my $padding = length($arc{'rev'});

	if (%list) {
		my @list = sort keys(%list);
		foreach my $file (@list) {
			say("F: $file") if @list > 1;
			my $i = 0;
			foreach my $rev (@{$list{$file}}) {
				$i++ if $opt{'showNumber'} > 0;
				last if $i > $opt{'showNumber'};
				say(sprintf("%${padding}d: %s", $rev, $note{$rev}));
			}
		}

	} else {
		err('None found.', 1);	
	}
}


#############
sub doMake {
#############
	$arc{'repos'} = SVN::Repos::create($opt{'archiveDirectory'}, undef, undef, undef, undef);
	say('C: ' . $opt{'archiveDirectory'});
}


#############
sub doMove {
#############
	my $tran = $arc{'fs'}->begin_txn($arc{'rev'});
	my $root = $tran->root;
	
	my $c = 0;
	
	foreach (@files) {
		if ($arc{'rev_root'}->check_path($_) != $SVN::Node::none) {

			# Make sure the target path is there
			my @pathTo = File::Spec->splitdir($opt{'targetDirectory'});
			my $path = '';

			while (@pathTo) {
				$path = File::Spec::Unix->join($path, shift @pathTo);
				if ($arc{'rev_root'}->check_path($path) == $SVN::Node::none) {
					say('A: ' . $path);
					$root->make_dir($path, SVN::Pool->new);
			    }
			}

			# a lot of work to do on this
			$root->hotcopy($_, $root, $path);
			say('M: ' . $_);

			$root->delete($_);
			say('D: ' . $_, 3);
			$c++;
		}
	}

	if ($c > 0) {
		my @rev = $tran->commit;
		$arc{'fs'}->change_rev_prop($rev[1], 'svn:log', $opt{'comment'}) if $opt{'comment'};

		say('V: ' . $rev[1], 2);
	} else {
		err('No changes.', 1);
	}
}


################
sub doRestore {
################
	my $c = 0;
	my %macro;
	my $template = $opt{'format'} || $opt{'restoreExtension'};

	$macro{'%V'} = $opt{'versionNumber'} || $arc{'rev'};
	my $root = $arc{'fs'}->revision_root($macro{'%V'});
	say("Opened revision " . $macro{'%V'}, 3);

	$macro{'%F'} = $arc{'fs'}->revision_prop($macro{'%V'}, 'svn:log') || '';
	$macro{'%K'} = $opt{'archiveDirectory'};
	$macro{'%s'} = str2time($arc{'fs'}->revision_prop($macro{'%V'}, 'svn:date'));
	$macro{'%v'} = $arc{'fs'}->revision_prop($macro{'%V'}, 'svn:author') || '?';

	foreach (@files) {
		if ($root->check_path($_) != $SVN::Node::none) {
			my @filename = File::Spec->splitpath($_);
			$macro{'%f'} = $filename[1];

			my $extension = $opt{'allowOverwrite'} ? '' : macroReplace($template, \%macro);
			my $dir = macroReplace($opt{'restoreDirectory'}, \%macro);

			my $filename = join ('', File::Spec->catpath($filename[0], $dir, $filename[2]), $extension);
			my $output = FileHandle->new("> $filename") || (err("Could not write $filename") && next);
			my $stream = $root->file_contents($_);
			my $txt; read($stream, $txt, $root->file_length($_));

			print $output $txt;
			close $stream;

			$output->close;
			say('R: ' . $filename);
			$c++;

		} else {
			say('N: ' . $_, 2);
		}
	}

	if ($c < 1) {
		err('Nothing restored.', 1);
	}
}


###############################################################################

###################
sub macroReplace {
###################
	my ($template, $macro) = @_;
	my %macro = %${macro};

	foreach (keys(%macro)) { $template =~ s/$_/$macro{$_}/mg; }
	return time2str($template, $macro{'%s'});
}


###################
sub makeFileList {
###################
	my @tmpfiles = @ARGV;
	my @dirs;
	
	if ($opt{'mode'} eq 'Move') {
		pod2usage(2) if @tmpfiles < 1;
		$opt{'targetDirectory'} = pop(@tmpfiles);
	}
	
	if ($opt{'all'}) {
		opendir(DH, $opt{'workingDirectory'});
		foreach (map $opt{'workingDirectory'} . "/$_", sort grep !/^\.\.?$/, readdir DH) {
			push @files, $_ if -f $_;
			push @dirs, $_ if -d $_;
		}

	} elsif ($opt{'fileList'} && -r $opt{'fileList'}) {
		open(FH, "<$opt{'fileList'}");
		push @tmpfiles, <FH>;
		close FH;

	} elsif ($opt{'fileList'}) {
		err("Unable to read file list.");
	}

	foreach (@tmpfiles) {
		chomp;
		my $path = File::Spec->rel2abs($_, $opt{'workingDirectory'});
		push @files, $path if -f $path;
		push @dirs, $path if -d $path;
	}
	
	if (@dirs && $opt{'recursive'}) {
		foreach (@dirs) {
			find({
				wanted => sub{ push @files, $_ if -f $_ }, 
				follow => 0,
				no_chdir => 1,
			}, $_);
		}
	}
	
	# @files is now an array of absolute paths to files
	@files > 0 || err("No files specified.", 1);
}


########################
sub setDefaultArchive {
########################
	say("Using default archive.", 2);
	$opt{'archiveDirectory'} = $ENV{'BACKUP_PATH'} || err("BACKUP_PATH not set", 1);
}


##############
sub setMode {
##############
	$opt{'mode'} && pod2usage(2);
	$opt{'mode'} = shift;
	say($opt{'mode'} . ' Mode.', 2);
}


###########
sub init {
###########
	Getopt::Long::Configure ("bundling");
	$SVN::Error::handler = sub { my $x = shift; err($x->message(), 4); };

	%opt = (
		'listFormat'		=> '%c - %F',
		'restoreExtension'	=> '.v%V_%Y%m%d_%H%M%S',
		'restoreDirectory'	=> '%f',
		'showNumber'		=> 10,
		'verbosity'		=> 1,
		'workingDirectory'	=> getcwd()
	);
	
	Getopt::Long::GetOptions(
		# unused:	gjuxy
		'h'	=> sub{ pod2usage(2); },
		'man'	=> sub{ pod2usage(-exitstatus => 0, -verbose => 2); },
		'version' => sub{ pod2usage(-exitstatus => 0, -verbose => 99, -sections => "VERSION"); },

		'd'	=> sub{ setMode('Diff'); },
		'k'	=> sub{ setMode('Make'); },
		'l'	=> sub{ setMode('List'); },
		'm'	=> sub{ setMode('Move'); },
		'r'	=> sub{ setMode('Restore'); },
		'z'	=> sub{ setMode('Delete'); },

		'a'	=> \$opt{'all'},
		'b+'	=> \$opt{'verbosity'},
		'c=s'	=> \$opt{'comment'},
		'e=s'	=> \$opt{'format'},
		'f=s'	=> \$opt{'fileList'},
		'i'	=> \$opt{'recursive'},
		'n=i'	=> \$opt{'showNumber'},
		'o'	=> \$opt{'allowOverwrite'},
		'p'	=> \$opt{'propogateMovement'},
		'q'	=> \$opt{'quiet'},
		's=s'	=> \$opt{'archiveDirectory'},
		't=s'	=> \$opt{'restoreDirectory'},
		'v=i'	=> \$opt{'versionNumber'},
		'w=s'	=> \$opt{'workingDirectory'},
	) || exit(1);

	$opt{'archiveDirectory'}	|| setDefaultArchive();
	$opt{'comment'}			= $opt{'comment'}
						? (getpwuid($<) . ': ' . $opt{'comment'})
						: (getpwuid($<) . ': no comment');
	$opt{'mode'}			|| setMode('Archive');
	$opt{'verbosity'}		= 0 if $opt{'quiet'};

	$SVN::Node::none;
}


###########
sub main {
###########
	if ($opt{'mode'} eq 'Make') {
		(! -d $opt{'archiveDirectory'}) || err("Directory exists", 2);
		doMake();

	} else {
		(-e $opt{'archiveDirectory'}) || err("Archive not found", 2);

		$arc{'pool'} = SVN::Pool->new_default;
		$arc{'repos'} = SVN::Repos::open($opt{'archiveDirectory'}) || err("Unable to open archive", 2);
		$arc{'fs'} = $arc{'repos'}->fs;
		$arc{'rev'} = $arc{'fs'}->youngest_rev;
		$arc{'rev_root'} = $arc{'fs'}->revision_root($arc{'rev'});
		
		makeFileList();
		eval 'do' . $opt{'mode'} . '()';
	}
}


exit;


__END__

=pod

=head1 NAME

backup - Instant, system wide version control.

=head1 SYNOPSIS

 backup [-abcfiqsw] [FILE...]                  = Add files to archive
 backup -d [-sv] FILE                          = Diff two files
 backup -k [-s] PATH                           = Make an archive
 backup -l [-abcefinsvw] [FILE...]             = List files in archive
 backup -m [-abcfipsw] [FILE...] PATH          = Move an archive file
 backup -r [-abefioqstvw] [FILE...]            = Restore an archive file
 backup -z [-abcfiqsvw] [FILE...]              = Delete an archive file

=head1 OPTIONS

=over 10

=item B<-a>

Operate against all files in the working directory

=item B<-b>

Display verbose output

=item B<-c> TEXT

Add a comment to, or show comments on an archive file

=item B<-e> EXT

Append extension to a restored file
(default: .v%V_%Y%M%D_%H%i%s)

=item B<-f> FILE

Operate against a given list of files
(overrides "-a")

=item B<-i>

Operate recursivly
(requires "-a" or "-f")

=item B<-n>

Show this many (maximum) results. Set to '0' to show all.
(default: 10)

=item B<-o>

Allow restore to overwrite files
(overrides "-e")

=item B<-p>

Propogate movement of a file to filesystem.

=item B<-q>

Quiet, no output
(overrides "-b")

=item B<-s> PATH

Storage path of the file archive
(default: $BACKUP_PATH)

=item B<-t>

Set the directory to restore to
(default: %f )

=item B<-v> #[,#]

Version number of file to list or restore
(default: latest)

=item B<-w> PATH

Change the working directory
(default: current)

=back

=head1 MACROS

Certain macros can be used in command line options as substitues
for variables. For example, in the default "-e" they are used to
append the date to restored files.

In addition to the following, you may use any macro available to
Date::Format. The time reflected is the time that the file was
archived.

=over 10

=item B<%F>

Log message given

=item B<%f>

Source path

=item B<%K>

Absolute path of the archive

=item B<%v>

Author who added/committed the file

=item B<%V>

Version number

=back

=head1 CODES

'backup' uses the following exit codes

=over 10

=item B<0>

No error

=item B<1>

User input, or usage error

=item B<2>

Configuration error

=item B<4>

Internal process error

=back

=head1 OUTPUT

'backup' uses the following output markers to identify changes or updates made:

=over 10

=item B<A:>

Added file/path to archive

=item B<C:>

Created archive

=item B<D:>

Deleted file in archive

=item B<F:>

File name

=item B<I:>

Ignored file

=item B<M:>

Moved file

=item B<N:>

Not found

=item B<R:>

Restored file

=item B<S:>

Skipped file

=item B<U:>

Updated file in archive

=item B<V:>

Archive Version

=back

=head1 VERSION

backup v0.2

=head1 AUTHOR

CJ Niemira <siege@siege.org>

=head1 COPYRIGHT

2008, CJ Niemira

=head1 LICENSE

This program is released under the GNU General Public License (GPL).

=cut
