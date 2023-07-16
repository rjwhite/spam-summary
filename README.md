# spam-summary - produce terse report of new SPAM mail since last run
*spam-summary* checks a mailbox of suspected spam and produces a report
showing new mail that arrived since the last run.

## Description
*spam-summary* checks one or more mailboxes that are suspected spam and
creates a report showing the sender and subject, one message per line,
of new messages that have arrived in that mailbox since the last time run.

A typical usage is that the user has mail forwarded, via a .forward file,
into procmail that has a number of rules to capture suspect spam mail,
and writes it to one or more spam mailboxes.  Typically, procmail is
making use of spamassassin.   Then *spam-summary* is typically run each
night from the crontab that looks at those mailboxes and produces a short
simple report showing address and subject - which is then mailed to you.

This way you can quickly verify that there are no false positives of real
mail that ended up as spam.  Since there should be a small number of new
spam messages each day, it is more manageable than wading through hundreds or
thousands over some irregular time interval by ocassionally checking manually.

It is driven by a config file to specify where the spam mailboxes are, and
where the timestamps are located.

You can specify patterns in the e-mail address to ignore from ongoing spammers
that have consistent forged addresses.

You can set in the config file the value of **find-hidden-sender** set to **yes** for
mailboxes that are typically bounced mail, with a **From** of MAILER-DAEMON.  This
value will result in *spam-summary* digging deeper to get the real **From**, possibly
even checking the body of the message as well as the header.

There are samples of .forward, .procmailrc and a *spam-summary* config file in
the directory named samples.

## config file
The config file is expected to be found in ${HOME}/etc/spam-summary/spam-summary.conf

An example config files can be found in the source directory named samples.

## Example config file

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

## Examples
    # usage

    server5> spam-summary --help
       usage: spam-summary [option]* [mail-folder]*
       [-c|--config file]  :default=/home/rj/etc/spam-summary/spam-summary.conf
       [-d|--debug]*       :debug mode (give twice for level=2)
       [-h|--help]         :usage
       [-i|--ignore]       :ignore timestamp file
       [-l|--list]         :list mail-folders available
       [-w|--wide]         :wide output
       [-V|--version]      :print version (0.2)
  

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
    # last removed, and we received 4 new messages since the last run
    # of which 1 was ignored because it had a rejected pattern.

    server5> spam-summary 'Probably Spam'
       New (valid) messages arrived for: Probably Spam
   
       yhzt@hhlkoj.ru  Louis Vuitton Bags Up To 87% Off! Shop Online Now!
       rj@moxad.com    Settle your debt in order to avoid additional fees.
       MAILER-DAEMON   Heres why your blood sugar is so erratic Consistent diet but...
   
       3 valid new messages out of 4 new messages and 106 total messages
       Ignoring 21 messages with an evil 'From ' field out of 106 total messages
       Ignoring 1 messages with an evil 'From ' field out of 4 new messages

## Timestamp files
*spam-summary* only shows messages since the last time it was run - unless you 
specify the -i or --ignore option to ignore the timestamp of the last run for
a particular folder.  The location of these timestamp files is specified in
the config file.  A typical timestamp file is given below.  The comments,
beginning with '#' are part of the file and are ignored by the program when 
reading it to get the numeric timestamp.

    # This timestamp file written by the spam-summary program
    # This timestamp is for the 'Probably Spam' mail folder
    # The timestamp below is Thu Oct 27 06:34:40 2022
    
    1666852480

## Requirements
*spam-summary*  uses  the  Moxad::Config  module  to handle human-readable
config files. This is available at https://github.com/rjwhite/Perl-config-module

## Maintenance
*spam-summary* does not do any cleanup of the spam mail folders.  It is up to
you to ocassionally remove them or remove really old messages from it.
Unless you have awful disk constraints and enormous amounts of spam mail,
you can probably clean them up every year or two.  Generally, you'd probably
do it when you see the **total messages** at the end of your daily report
become some large number - like many thousands.
