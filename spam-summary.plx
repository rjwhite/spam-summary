#!/usr/bin/env perl

# produce a summary of mail found in one or more mail folders that are
# likely spam.  The intention is that these spam folders are typically
# ignored for months at a time where a false positive may be lurking.
# This program, typically run from the crontab, keeps a timestamp for
# each folder so that each time it runs, it produces a summary of what 
# it has not yet seen - showing the From and Subject - so that if something
# looks like real mail, it can be investigated.

# It gets info from a config file.  See the config file for where the
# program keeps its info

# A special case is the 'find-hidden-sender' config option which is
# typically used for a folder of bounced messages, typically from 
# MAILER-DAEMON. This 'find-hidden-sender' option will try to get
# the real From and Subject,  from within the body of the message
# if necessary.  Throughout the program, we refer to this as a
# bounced message and the bounce flag.

#   spam-summary --help             # usage
#   spam-summary  --list            # to see available folders
#   spam-summary 'Probably Spam'    # The 'Probably Spam' folder

use strict ;
use warnings ;
use File::Basename ;
use File::Path qw( make_path ) ;
use Time::Local ;
use Encode qw( decode ) ;
use lib "/usr/local/Moxad/lib" ;
use Moxad::Config ;

my $G_progname    = $0 ;
my $G_version     = "0.3" ;
my $G_debug_flag  = 0 ;

my $C_FOLDER      = 'folder' ;
my $C_TITLE       = 'title' ;
my $C_BOUNCE_FLAG = 'find-hidden-sender' ;
my $C_TIMESTAMP   = 'timestamp-file' ;
my $C_PATTERNS    = 'ignore-from-patterns' ;
my $C_VARIABLES   = 'variables' ;
my $C_CHOP_USER   = 'address-max-len' ;

my $C_DEFAULT_CHOP_USER = 60 ;

$G_progname      =~ s/^.*\/// ;


# Let er rip...


if ( main()) {
    exit(1) ;
} else {
    exit(0) ;
}



sub main {
    my $help_flag   = 0 ;
    my $list_flag   = 0 ;
    my $ignore_flag = 0 ;
    my $num_columns = 80 ;
    my @folders     = () ;

    my $home = $ENV{ 'HOME' } ;
    my $config_file = "${home}/etc/spam-summary/spam-summary.conf" ;

    for ( my $i = 0 ; $i <= $#ARGV ; $i++ ) {
        my $arg = $ARGV[ $i ] ;
        if (( $arg eq "-h" ) or ( $arg eq "--help" )) {
            $help_flag++ ;
        } elsif (( $arg eq "-V" ) or ( $arg eq "--version" )) {
            print "version: $G_version\n" ;
            return(0) ;
        } elsif (( $arg eq "-w" ) or ( $arg eq "--wide" )) {
            $num_columns = 132 ;
        } elsif (( $arg eq "-d" ) or ( $arg eq "--debug" )) {
            $G_debug_flag++ ;
        } elsif (( $arg eq "-l" ) or ( $arg eq "--list" )) {
            $list_flag++ ;
        } elsif (( $arg eq "-i" ) or ( $arg eq "--ignore" )) {
            $ignore_flag++ ;
        } elsif (( $arg eq "-c" ) or ( $arg eq "--config" )) {
            $config_file = $ARGV[ ++$i ] ;
        } elsif ( $arg =~ /^\-/ ) {
            print STDERR "$G_progname: unknown option: $arg\n" ;
            return(1) ;
        } else {
            push( @folders, $arg ) ;
        }
    }

    my $use_all_folders = 0 ;
    if ( @folders == 0 ) {
        dprint( "Processing ALL folders found in $config_file" ) ;
        $use_all_folders = 1 ;
    }

    if ( $help_flag ) {
        print "usage: $G_progname [option]* [mail-folder]*\n" ;
        print "   [-c|--config file]  :default=$config_file\n" ;
        print "   [-d|--debug]*       :debug mode (give twice for level=2)\n" ;
        print "   [-h|--help]         :usage\n" ;
        print "   [-i|--ignore]       :ignore timestamp file\n" ;
        print "   [-l|--list]         :list mail-folders available\n" ;
        print "   [-w|--wide]         :wide output\n" ;
        print "   [-V|--version]      :print version ($G_version)\n" ;

        return(0) ;
    }

    Moxad::Config->set_debug( $G_debug_flag ) ;

    my $cfg1 = Moxad::Config->new( $config_file, "" ) ;
    if ( $cfg1->errors() ) {
        my @errors = $cfg1->errors() ;
        foreach my $error ( @errors ) {
            print STDERR "$G_progname: $error\n" ;
        }
        return(1) ;
    }
    my @sections = $cfg1->get_sections() ;      # get sections

    my %values = () ;
    foreach my $section ( @sections ) {
        if ( $use_all_folders ) {
            if ( $section ne $C_VARIABLES ) {
                push( @folders, $section ) ;
            }
        }

        my @keywords = $cfg1->get_keywords( $section ) ;  # get keywords
        foreach my $keyword ( @keywords ) {
            # everything is a scalar
            my $value = $cfg1->get_values( $section, $keyword ) ;
            $values{ $section }{ $keyword } = $value ;
        }
    }

    if ( $list_flag ) {
        print "folders:\n" ;
        foreach my $section ( @sections ) {
            next if ( $section eq $C_VARIABLES ) ;
            my $file = get_value( $section, \%values, $C_FOLDER ) ;
            $file = '???' if ( not defined( $file )) ;
            printf( "    %-20s (%s)\n", $section, $file ) ;
        }
        return(0) ;
    }

    foreach my $folder ( @folders ) {
        my @from_patterns = () ;
        dprint( "processing folder: $folder" ) ;
        if ( not defined( $values{ $folder } )) {
            print STDERR "$G_progname: No such folder: $folder\n" ;
            print STDERR "$G_progname: Try using --list option\n" ;
            return(1) ;
        }

        # get num chars to chop in username
        my $max_user_len = get_value( $folder, \%values, $C_CHOP_USER,
                                       $C_DEFAULT_CHOP_USER ) ;
        dprint( "chopping username at $max_user_len characters" ) ;

        # get the folder location
        my $folder_file = get_value( $folder, \%values, $C_FOLDER ) ;

        # skip if folder does not exist.  Like for a 'test' entry in the config
        if ( $folder_file eq "" ) {
            dprint( "folder does not exist for \'$folder\'" ) ;
            next ;
        }
        if ( ! -f $folder_file ) {
            dprint( "No such mail folder ($folder_file) for \'$folder\'" ) ;
            next ;
        }
        dprint( "folder location is $folder_file" ) ;

        my $last_time = 0 ;
        my $timestamp_file ;
        if ( $ignore_flag == 0 ) {
            # get the timestamp file location
            $timestamp_file = get_value( $folder, \%values, $C_TIMESTAMP ) ;
            return(1) if ( $timestamp_file eq "" ) ;
            dprint( "timestamp file location is  = $timestamp_file" ) ;
            return(1) if ( get_timestamp( $timestamp_file, \$last_time )) ;
            dprint( "last time timestamp for $folder is $last_time" ) ;
        } else {
            dprint( "ignoring time-stamp file for $folder_file" ) ;
        }

        # get the title
        my $title = get_value( $folder, \%values, $C_TITLE ) ;
        if (( not defined( $title )) or ( $title eq "" )) {
            $title = $folder ;
        }
        dprint( "title = $title" ) ;

        # see if it is bounced mail that needs to be processed differently
        my $bounce_flag = 0 ;
        my $value = $values{ $folder }{ $C_BOUNCE_FLAG } ;
        if ( defined( $value )) {
            $value =~ tr/A-Z/a-z/ ;
            $bounce_flag = 1 if ( $value =~ /yes/ )  ;
        }
        dprint( "bounced mail flag is $bounce_flag", 2 ) ;

        # see if there are patterns to watch for in the From to ignore
        my $patterns_flag = 0 ;
        my $pattern_file = get_value( $folder, \%values, $C_PATTERNS ) ;
        if (( defined( $pattern_file )) and ( $pattern_file ne "" )) {
            @from_patterns = read_from_patterns( $pattern_file ) ;
            dprint( "From patterns to look for found in $pattern_file", 2 ) ;
        }

        return(1) if ( process_mailbox( $folder_file, $last_time, $title, 
                                        \@from_patterns, $bounce_flag,
                                        $num_columns, $max_user_len )) ;

        if ( $ignore_flag == 0 ) {
            return(1) if ( write_timestamp( $timestamp_file, $title )) ;
        }
    }
    return(0) ;
}


# read a bunch of patterns to watch for in the 'From' field for
# messages we want to ignore.
# For eg:  A 'From' containing ...-rj=moxad.com@mail.... will be crap
#
# Arguments:
#   1:  file to read
# Returns:
#   array of patterns
# Globals:
#   none

sub read_from_patterns {
    my $file = shift ;

    my @patterns = () ;
    return( [] ) if ( ! -f $file )  ;

    my $fh ;
    if ( ! open( $fh, "<", $file )) {
        return( [] ) ;
    }
    my @lines = <$fh> ;
    foreach my $line ( @lines ) {
        chomp( $line ) ;
        next if ( $line eq "" ) ;
        next if ( $line =~ /^#/ ) ;
        push( @patterns, $line ) ;
    }
    close( $fh ) ;

    return( @patterns ) ;
}


# write a timestamp to a file
#
# Arguments:
#   1: filename
#   2: title (provided in config file)
# Returns:
#   0: ok
#   1: not-ok
# Globals:
#   $G_progname

sub write_timestamp {
    my $file = shift ;
    my $title = shift ;

    # make any missing (sub)directories

    my $dirname = dirname( $file ) ;
    if ( ! -d $dirname ) {
        make_path( $dirname ) ;
    }

    my $fh ;
    if ( ! open( $fh, ">", $file )) {
        print STDERR "$G_progname: can't open: $file\n" ;
        return(1) ;
    }

    my $now = time() ;
    my $pretty_date = gmtime();

    print $fh "\# This timestamp file written by the $G_progname program\n" ;
    print $fh "\# This timestamp is for the \'$title\' mail folder\n" ;
    print $fh "\# The timestamp below is $pretty_date\n\n" ;
    print $fh "$now\n" ;
    close( $fh ) ;

    dprint( "timestamp written to $file" ) ;
    return(0) ;
}


# process a mail folder.
# This will print a list of From and Subject of messages not yet seen.
# It will format the list, one message per line so that enough room is
# provided for the longest From address seen.  Subjects that are too 
# long to fit within a 80 character line are truncated and indicated
# by ending them with '...'
#
# Arguments:
#   1: filename
#   2: timestamp of last run
#   3: title (from the config file
#   4: reference to array of patyterns in From to ignore
#   5: bounce flag (1=yes, 0=no - default = 0)
#   6: number of columns wide of report
#   7: maxiumum length of username
# Returns:
#   0: ok
#   1: not-ok
# Globals:
#   $G_progname

sub process_mailbox {
    my $file         = shift ;
    my $last_time    = shift ;
    my $title        = shift ;
    my $patterns_ref = shift ;
    my $b_flag       = shift ;
    my $num_columns  = shift ;
    my $max_user_len = shift ;

    my %months = ( 'Jan' => 1,  'Feb' => 2,  'Mar' => 3,  'Apr' => 4,  
                   'May' => 5,  'Jun' => 6,  'Jul' => 7,  'Aug' => 8,
                   'Sep' => 9,  'Oct' => 10, 'Nov' => 11, 'Dec' => 12 ) ;

    my @froms = () ;
    my @subjects = () ;

    $max_user_len = $C_DEFAULT_CHOP_USER if ( not defined( $max_user_len )) ;

    if ( ! -f $file ) {
        # cant happen
        print STDERR "$G_progname: no such mail folder $file\n" ;
        return(1) ;
    }
    my $fh ;
    if ( ! open( $fh, "<", $file )) {
        print STDERR "$G_progname: can't open: $file\n" ;
        return(1) ;
    }

    my $num_messages = 0 ;
    my $in_header = 0 ;
    my $line_number = 0 ;
    my $from = "" ;
    my $msg_time = 0 ;
    my $date = "" ;
    my $subject = "" ;
    my $skip_flag = 0 ;
    my $num_pattern_match_all = 0 ;
    my $num_pattern_match_new = 0 ;
    my $invalid_date_count = 0 ;
    my $new_messages = 0 ;
    while ( my $line = <$fh> ) {
        chomp( $line ) ;
        $line_number++ ;
        if ( $in_header ) {
            # in the header
            if ( $line eq "" ) {
                $in_header = 0 ;
                dprint( "No longer in header on line \#$line_number", 2 ) ;
            } elsif ( $line =~ /^Subject: / ) {
                $subject = $line ;
                $subject =~ s/^Subject: // ;
            } elsif ( $line =~ /^Date: / ) {
                $date = $line ;
                $date =~ s/^Date: // ;

                if ( $date !~ /^[\d\w\s\+\-,:\(\)]+$/ ) {
                    $invalid_date_count++ ;
                    my $error = "invalid date in message \#$num_messages: $date" ;
                    dprint( $error, 2 ) ;
                    next ;
                }
                # date is of format:  26 Dec 2019 14:41:24 ...
                # get rid of preceeding day
                $date =~ s/^[\w]+,\s*// if ( $date =~ /^[\w]+,\s*/ ) ;

                my ( $mday, $month, $year, $hour, $min, $sec ) = 
                    split(/[\s.:]+/, $date) ;

                if (( $hour < 0 ) or ( $hour > 23 )) {
                    $invalid_date_count++ ;
                    my $error = "invalid date in message \#$num_messages: $date" ;
                    dprint( $error, 2 ) ;
                    next ;
                }
                my $mon = $months{ $month } ;
                if ( not defined( $mon )) {
                    my $error = "could not convert month ($month) in $date" ;
                    print STDERR "$G_progname: $error\n" ;
                    $error = "setting month to 1 (Jan) in msg \#$num_messages " .
                             "in $file" ;
                    print STDERR "$G_progname: $error\n" ;
                    $mon = 1 ;
                }
                $msg_time = timelocal( $sec, $min, $hour, $mday, $mon-1, $year );
            } elsif ( $b_flag and ( $line =~ /^From: */ )) {
                # we probably don't want this 'From:' and want one found
                # for bounced mail within the body to over-ride this.
                # But sometimes there isn't one in the body and this one is
                # our only real indicator of who sent it.

                $from = $line ;
                $from =~ s/^From: *// ;
                my $msg = "${num_messages}: got bounced \'From:\' IN HEADER on line " .
                          "\#${line_number}: $from" ;
                dprint( $msg, 2 ) ;
            }
        } else {
            # no longer in the header
            if ( $line =~ /^From / ) {
                dprint( "Got a \'From \' on line \#$line_number: $line", 2 ) ;
                $in_header = 1 ;
                $num_messages++ ;

                # process previous entry (if there was one)
                if ( $from ne "" ) {
                    if ( $msg_time > $last_time ) {
                        $new_messages++ ;
                        if ( $skip_flag ) {
                            $num_pattern_match_new++ ;
                        } else {
                            dprint( "reporting msg using Date of \'$date\'", 2 ) ;
                            $from = clean_up_address( $from, $max_user_len ) ;
                            push( @froms, $from ) ;
                            push( @subjects, $subject ) ;
                        }
                    }
                }

                $from = $line ;
                $from =~ s/^From // ;
                $from =~ s/\s+.*$// ;

                # see if we should ignore it
                $skip_flag = 0 ;
                foreach my $pat ( @{$patterns_ref} ) {
                    if ( $from =~ /$pat/ ) {
                        dprint( "skipping evil from address: \'$from\'" ) ;
                        $skip_flag++ ;
                        last ;
                    }
                }
                if ( $skip_flag ) {
                    $num_pattern_match_all++ ;
                } 
                $subject = "" ;     # reset
                $date = "" ;        # reset
                $msg_time = 0 ;     # reset
            } else {
                if ( $b_flag ) {
                    if ( $line =~ /^From: */ ) {
                        # we're handling bounced mail, from MAILER-DAEMON
                        # get the original From and Subject from inside
                        # the body

                        $from = $line ;
                        $from =~ s/^From: *// ;
                        my $msg = "${num_messages}: got a bounced \'From:\' IN BODY on line " .
                                  "\#${line_number}: $from" ;
                        dprint( $msg, 2 ) ;
                    } elsif ( $line =~ /^Subject: / ) {
                        $subject = $line ;
                        $subject =~ s/^Subject: // ;
                    }
                }
            }
        }
    }
    # and process final entry
    if ( $from ne "" ) {
        if ( $msg_time > $last_time ) {
            $new_messages++ ;
            if ( $skip_flag ) {
                $num_pattern_match_new++ ;
            } else {
                dprint( "reporting msg using Date of \'$date\'", 2 ) ;
                $from = clean_up_address( $from, $max_user_len ) ;
                push( @froms, $from ) ;
                push( @subjects, $subject ) ;
            }
        }
    }
    close( $fh ) ;

    my $msg = "we have $num_messages total messages in $file" ;
    dprint( $msg, 2 ) ;

    if ( @froms > 0 )  {
        print "\nNew (valid) messages arrived for: $title\n\n" ;
    }
    
    my $max_size_of_from = 0 ;
    my $num_elements = 0 ;
    foreach my $from ( @froms ) {
        $num_elements++ ;
        my $len = length( $from ) ;
        if ( $len > $max_size_of_from ) {
            $max_size_of_from = $len ;
        }
    }
    $max_size_of_from++ ;
    my $max_size_of_subject = $num_columns - 5 - $max_size_of_from ;
    for ( my $i = 0 ; $i < $num_elements ; $i++ ) {
        my $from = $froms[ $i ] ;
        my $subject = $subjects[ $i ] ;
        $subject = decode_subject( $subject ) ;     # in case of UTF encoded
        my $len = length( $subject ) ;
        if ( $len > $max_size_of_subject ) {
            $subject = substr( $subject, 0, $max_size_of_subject ) . "..." ;
        }
        my $str = sprintf( "%-${max_size_of_from}s %-${max_size_of_subject}s",
            $from, $subject ) ;
        $str =~ s/  *$// ;
        print "$str\n" ;
    }

    if ( $num_elements ) {
        print "\n${num_elements} valid new messages out of " .
            "$new_messages new messages and $num_messages total messages\n" ;

        if ( $num_pattern_match_all ) {
            print "Ignoring $num_pattern_match_all messages with an evil " .
                  "\'From \' field out of $num_messages total messages\n" ;
        }
        if ( $num_pattern_match_new ) {
            print "Ignoring $num_pattern_match_new messages with an evil " .
                  "\'From \' field out of $new_messages new messages\n" ;
        }
        if ( $invalid_date_count ) {
            print "Found $invalid_date_count messages with an invalid date " .
                "out of $num_messages total messages\n" ;
        }
    }
    return(0) ;
}

# read the timestamp for the mail folder showing when we last ran 
# for that mail folder.
#
# Arguments:
#   1: filename
#   2: timestamp of last run
# Returns:
#   0: ok
#   1: not-ok
# Globals:
#   $G_progname

sub get_timestamp {
    my $file = shift ;
    my $last_time_ref = shift ;

    if ( ! -f $file ) {
        ${$last_time_ref} = 0 ;
        return(0) ;
    }

    my $fh ;
    if ( ! open( $fh, "<", $file )) {
        print STDERR "$G_progname: can't open: $file\n" ;
        return(1) ;
    }
    my @lines = <$fh> ;
    foreach my $line ( @lines ) {
        chomp( $line ) ;
        next if ( $line eq "" ) ;
        next if ( $line =~ /^\#/ ) ;

        $$last_time_ref = $line ;

        close( $fh ) ;
        return(0) ;
    }

    # didn't find it
    close( $fh ) ;
    ${$last_time_ref} = 0 ;
    return(0) ;
}


# get a value from the config file for a mail folder
# Any variables in the entry found are expanded.
# eg: For the entry:
#       Probably Spam:
#           folder = ${folder-dir}/spam/probably-spam
# the varible 'folder-dir' is expanded.
# variables are found in the 'variables' section of the config file.
#
# Arguments:
#   1: mail folder (section name in config file - eg: 'Probably Spam'
#   2: reference of hash of values from config file
#   3: name of the value we want.  eg: 'timestamp-file'
#   4: optional default to use if value not found
# Returns:
#   value   - success
#   ""      - error
# Globals:
#   $G_progname

sub get_value {
    my $folder     = shift ;
    my $values_ref = shift ;
    my $key        = shift ;
    my $default    = shift ;

    my $str = $$values_ref{ $folder }{ $key } ;
    if ( not defined( $str )) {
        if ( defined( $default )) {
            return( $default ) ;
        } else {
            dprint( "Could not value for \'$key\' for $folder" ) ;
            return( "" ) ;
        }
    }

    # expand variables of form ${key}

    if ( $str =~ /\$\{([\w\d\-\.\/]+)\}/ ) {
        my $value = $$values_ref{ $C_VARIABLES }{ $1 } ;
        if ( defined( $value )) {
            $str =~ s/\$\{$1\}/$value/g ;
            return( $str ) ;
        }
    }

    return( $str ) ;        # return original string
}


# print Debug string if debug flag >= to debug level provided
# The optional level defaults to 1.  ie: a single -d/--debug
#
# Arguments:
#   1: message
#   2: debug level
# Returns:
#   0
# Globals:
#   $G_debug_flag

sub dprint {
    my $msg   = shift ;
    my $level = shift ;

    $level = 1 if ( not defined( $level )) ;

    return(0) if ( $G_debug_flag == 0 ) ;

    print "debug: $msg\n" if ( $G_debug_flag >= $level ) ;
    return(0) ;
}


# clean up and possibly truncate the e-mail address
#
# Arguments:
#   1: e-mail address
#   2: max lenth
# Returns:
#   address
# Globals:
#   none

sub clean_up_address {
    my $addr = shift ;
    my $max_len = shift ;

    # throw away the descriptive name for address
    $addr = $1 if ( $addr =~ /<([\w\d\.\-\@]+)>/ ) ;
    # now chop if too long
    if ( length( $addr ) > $max_len ) {
        $addr = substr( $addr , 0, $max_len) . "..." ;
    }
    return( $addr ) ;
}


# decode a Subject line if it is UTF encoded
# sets binmode on STDOUT appropriately for any future prints
#
# Arguments:
#   subject line
# Returns:
#   subject
# Globals:
#   none

sub decode_subject {
    my $subject = shift ;

    binmode( STDOUT ) ;     # default

    if ( $subject !~ /=\?UTF-8/i ) {
        return( $subject ) ;
    }

    # got a UTF-8 line
    my $str = decode( "MIME-Header", $subject, Encode::FB_QUIET ) ;
    if (( not defined( $str )) or ( $str eq "" )) {
        return( $subject ) ;
    }

    # To get rid of errors like:
    #       Wide character in print at spam-summary line nnn
    binmode( STDOUT, "encoding(UTF-8)") ;

    return( $str ) ;
}


__END__
=head1 NAME

spam-summary - produce terse report of new SPAM mail since last run

=head1 SYNOPSIS

spam-summary [option]* [mail-folder]*

=head1 DESCRIPTION

I<spam-summary> checks one or more mailboxes that are suspected spam and
creates a report showing the sender and subject, one message per line,
of new messages that have arrived in that mailbox since the last time run.

A typical usage is that the user has mail forwarded, via a .forward file,
into procmail that has a number of rules to capture suspect spam mail,
and writes it to one or more spam mailboxes.  Typically, procmail is
making use of I<spamassassin>.   Then I<spam-summary> is typically run each
night from the crontab that looks at those mailboxes and produces a short
simple report showing address and subject - which is then mailed to you.

This way you can quickly verify that there are no false positives of
real mail that ended up as spam.  Since there should be a small number
of new spam messages each day, it is more manageable than wading through
hundreds or thousands over some irregular time interval by ocassionally
checking manually.

It is driven by a config file to specify where the spam mailboxes are, and
where the timestamps are located.

You can specify patterns in the e-mail address to ignore from ongoing spammers
that have consistent forged addresses.

You can set in the config file the value of B<find-hidden-sender> set to B<yes> for
mailboxes that are typically bounced mail, with a B<From> of MAILER-DAEMON.  This
value will result in I<spam-summary> digging deeper to get the real B<From>, possibly
even checking the body of the message as well as the header.

There are samples of .forward, .procmailrc and a I<spam-summary> config file in
the directory named samples.

=head1 OPTIONS

   -c  or --config     provide a file name to use instead of the default
   -d  or --debug      debug mode (give twice for level=2)
   -h  or --help       usage
   -i  or --ignore     ignore the timestamp file and process the whole file
   -l  or --list       list all the mail-folders available
   -w  or --wide       wide output - 132 characters
   -V  or --version    print the version

=head1 CONFIG FILE

The config file is expected to be found in ${HOME}/etc/spam-summary/spam-summary.conf

An example config file can be found in the source directory named samples.

=head1 EXAMPLE CONFIG FILE

 # variables to expand in entries
 variables:
     main-dir        = /home/rj/etc/spam-summary
     timestamp-dir   = /home/rj/etc/spam-summary/time-stamps
     folder-dir      = /home/rj/Mutt-mail
     address-len-max = 22
 
 Likely Spam:
     title                   = Almost Certainly Spam
     folder                  = ${folder-dir}/spam/almost-certainly-spam
     timestamp-file          = ${timestamp-dir}/likely.txt
     ignore-from-patterns    = ${main-dir}/from-patterns.txt
     address-max-len         = ${address-len-max}
 
 Probably Spam:
     title                   = Probably Spam
     folder                  = ${folder-dir}/spam/probably-spam
     timestamp-file          = ${timestamp-dir}/probably.txt
     ignore-from-patterns    = ${main-dir}/from-patterns.txt
     address-max-len         = ${address-len-max}
 
 Best TLD:
     title                   = Crap from the Best Top Level Domain
     folder                  = ${folder-dir}/spam/best-top-level-domain
     timestamp-file          = ${timestamp-dir}/best-TLD.txt 
     ignore-from-patterns    = ${main-dir}/from-patterns.txt
     address-max-len         = ${address-len-max}
 
 mailer-daemon:
     title                   = Bounced Mail
     folder                  = ${folder-dir}/mailer-daemon
     timestamp-file          = ${timestamp-dir}/mailer-daemon.txt
     ignore-from-patterns    = ${main-dir}/from-patterns.txt
     address-max-len         = ${address-len-max}
     find-hidden-sender      = yes

=head1 EXAMPLES

 # usage
 
 server5> spam-summary --help
   usage: spam-summary [option]* [mail-folder]*
   [-c|--config] file  :default=/home/rj/etc/spam-summary/spam-summary.conf
   [-d|--debug]*       :debug mode (give twice for level=2)
   [-h|--help]         :usage
   [-i|--ignore]       :ignore timestamp file
   [-l|--list]         :list mail-folders available
   [-w|--wide]         :wide output
   [-V|--version]      :print version (0.1)
 
 
 # show what folders are specified in the config file
 
 server5> spam-summary --list
   folders:
       Likely Spam      (/home/rj/Mutt-mail/spam/almost-certainly-spam)
       Probably Spam    (/home/rj/Mutt-mail/spam/probably-spam)
       Best TLD         (/home/rj/Mutt-mail/spam/best-top-level-domain)
       mailer-daemon    (/home/rj/Mutt-mail/mailer-daemon)
 
 
 # You can see here spammers forging addresses from my domain moxad.com
 # but it's obvious from the subject that all of these are spam.
 # The ignored 'evil' addresses are because they had patterns matched
 # by the 'ignore-from-patterns' directive in the config file.
 # In this case, I had specified a pattern of '-rj=moxad.com@'
 # This mailbox has a total of 106 messages since the mailbox was
 # last removed, and we received 5 new messages since the last run
 # of which 1 was ignored because it had a rejected pattern.
 
 server5> spam-summary 'Probably Spam'
   New (valid) messages arrived for: Probably Spam

   yhzt@hhlkoj.ru  Louis Vuitton Bags Up To 87% Off! Shop Online Now!
   rj@moxad.com    Settle your debt in order to avoid additional fees.
   MAILER-DAEMON   Heres why your blood sugar is so erratic Consistent diet but...

   3 valid new messages out of 4 new messages and 106 total messages
   Ignoring 21 messages with an evil 'From ' field out of 106 total messages
   Ignoring 1 messages with an evil 'From ' field out of 4 new messages

=head1 TIMESTAMP FILES

I<spam-summary> only shows messages since the last time it was run - unless you 
specify the -i or --ignore option to ignore the timestamp of the last run for
a particular folder.  The location of these timestamp files is specified in
the config file.  A typical timestamp file is given below.  The comments,
beginning with '#' are part of the file and are ignored by the program when 
reading it to get the numeric timestamp.

 # This timestamp file written by the spam-summary program
 # This timestamp is for the 'Probably Spam' mail folder
 # The timestamp below is Thu Oct 27 06:34:40 2022
    
 1666852480

=head1 MAINTENANCE

I<spam-summary> does not do any cleanup of the spam mail folders.  It is
up to you to ocassionally remove them or remove really old messages
from it.  Unless you have awful disk constraints and enormous amounts of
spam mail, you can probably clean them up every year or two.  Generally,
you'd probably do it when you see the B<total messages> at the end of
your daily report become some large number - like many thousands.

=head1 AUTHOR

RJ White
rj.white@moxad.com
