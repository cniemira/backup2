# backup2

Archived for posterity

## manpage

    NAME
    backup - Instant, system wide version control.

    SYNOPSIS
    backup [-abcfiqsw] [FILE...]                  = Add files to archive
    backup -d [-sv] FILE                          = Diff two files
    backup -k [-s] PATH                           = Make an archive
    backup -l [-abcefinsvw] [FILE...]             = List files in archive
    backup -m [-abcfipsw] [FILE...] PATH          = Move an archive file
    backup -r [-abefioqstvw] [FILE...]            = Restore an archive file
    backup -z [-abcfiqsvw] [FILE...]              = Delete an archive file

    OPTIONS
    -a        Operate against all files in the working directory

    -b        Display verbose output

    -c TEXT   Add a comment to, or show comments on an archive file

    -e EXT    Append extension to a restored file (default:
              .v%V_%Y%M%D_%H%i%s)

    -f FILE   Operate against a given list of files (overrides "-a")

    -i        Operate recursivly (requires "-a" or "-f")

    -n        Show this many (maximum) results. Set to '0' to show all.
              (default: 10)

    -o        Allow restore to overwrite files (overrides "-e")

    -p        Propogate movement of a file to filesystem.

    -q        Quiet, no output (overrides "-b")

    -s PATH   Storage path of the file archive (default: $BACKUP_PATH)

    -t        Set the directory to restore to (default: %f )

    -v #[,#]  Version number of file to list or restore (default: latest)

    -w PATH   Change the working directory (default: current)

    MACROS
    Certain macros can be used in command line options as substitues for
    variables. For example, in the default "-e" they are used to append the
    date to restored files.

    In addition to the following, you may use any macro available to
    Date::Format. The time reflected is the time that the file was archived.

    %F        Log message given

    %f        Source path

    %K        Absolute path of the archive

    %v        Author who added/committed the file

    %V        Version number

    CODES
    'backup' uses the following exit codes

    0         No error

    1         User input, or usage error

    2         Configuration error

    4         Internal process error

    OUTPUT
    'backup' uses the following output markers to identify changes or
    updates made:

    A:        Added file/path to archive

    C:        Created archive

    D:        Deleted file in archive

    F:        File name

    I:        Ignored file

    M:        Moved file

    N:        Not found

    R:        Restored file

    S:        Skipped file

    U:        Updated file in archive

    V:        Archive Version

    VERSION
    backup v0.2

    AUTHOR
    CJ Niemira <siege@siege.org>

    COPYRIGHT
    2008, CJ Niemira

    LICENSE
    This program is released under the GNU General Public License (GPL).
