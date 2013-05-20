package Mail::DMARC;
use strict;
use warnings;

use Carp;

use parent 'Mail::DMARC::Base';
require Mail::DMARC::Policy;
require Mail::DMARC::Report;
require Mail::DMARC::Result;

sub source_ip {
    return $_[0]->{source_ip} if 1 == scalar @_;
    croak "invalid source_ip" if ! $_[0]->is_valid_ip($_[1]);
    return $_[0]->{source_ip} = $_[1];
};

sub envelope_to {
    return $_[0]->{envelope_to} if 1 == scalar @_;
    croak "invalid envelope_to" if ! $_[0]->is_valid_domain($_[1]);
    return $_[0]->{envelope_to} = $_[1];
};

sub envelope_from {
    return $_[0]->{envelope_from} if 1 == scalar @_;
    croak "invalid envelope_from" if ! $_[0]->is_valid_domain($_[1]);
    return $_[0]->{envelope_from} = $_[1];
};

sub header_from {
    return $_[0]->{header_from} if 1 == scalar @_;
    croak "invalid header_from" if ! $_[0]->is_valid_domain($_[1]);
    return $_[0]->{header_from} = $_[1];
};

sub header_from_raw {
    return $_[0]->{header_from_raw} if 1 == scalar @_;
#croak "invalid header_from_raw: $_[1]" if 'from:' ne lc substr($_[1], 0, 5);
    return $_[0]->{header_from_raw} = $_[1];
};

sub local_policy {
    return $_[0]->{local_policy} if 1 == scalar @_;
# TODO: document this, when and why it would be used
    return $_[0]->{local_policy} = $_[1];
};

sub dkim {
    my ($self, $dkim) = @_;
    return $self->{dkim} if ! $dkim;

    if ( ref $dkim && ref $dkim eq 'Mail::DKIM::Verifier' ) {
        return $self->dkim_from_mail_dkim($dkim);
    };

    if ( 'ARRAY' ne ref $dkim ) {
        croak "dkim must be an array reference!";
    };
    foreach my $s ( @$dkim ) {
        foreach my $f ( qw/ domain result / ) {
            croak "DKIM '$f' is required!" if ! $s->{$f};
        };
    };
    return $self->{dkim} = $dkim;
};

sub dkim_from_mail_dkim {
    my ($self, $dkim) = @_;
# A DKIM verifier will have result and signature methods.
    foreach my $s ( $dkim->signatures ) {
        push @{ $self->{dkim} }, {
            domain       => $s->domain,
            selector     => $s->selector,
            result       => $s->result,
            human_result => $s->result_detail,
        };
    };
    return $self->{dkim};
};

sub spf {
    my ($self, @args) = @_;
    return $self->{spf} if 0 == scalar @args;

    if ( scalar @args == 1 && ref $args[0] && ref $args[0] eq 'HASH' ) {
        return $self->{spf} = $args[0];
    };

    croak "invalid arguments" if @args % 2 != 0;
    $self->{spf} = { @args };
    $self->is_valid_spf();
    return $self->{spf};
};

sub policy {
    my ($self, @args) = @_;
    return $self->{policy} if ref $self->{policy} && 0 == scalar @args;
    return $self->{policy} = Mail::DMARC::Policy->new(@args);
};

sub report {
    my $self = shift;
    return $self->{report} if ref $self->{report};
    return $self->{report} = Mail::DMARC::Report->new();
};

sub result {
    my $self = shift;
    return $self->{result} if ref $self->{result};
    return $self->{result} = Mail::DMARC::Result->new();
};

sub is_subdomain {
    return $_[0]->{is_subdomain} if 1 == scalar @_;
    croak "invalid boolean" if 0 == grep {/^$_[1]$/ix} qw/ 0 1/;
    return $_[0]->{is_subdomain} = $_[1];
};

sub is_valid_spf {
    my $self = shift;
    foreach my $f ( qw/ domain result scope / ) {
        if ( ! $self->{spf}{$f} ) {
            croak "SPF $f is required!";
        };
    };
    if ( ! grep {$_ eq lc $self->{spf}{scope}} qw/ mfrom helo / ) {
        croak "invalid SPF scope!";
    };
    if ( $self->{spf}{result} eq 'pass' && ! $self->{spf}{domain} ) {
        croak "SPF pass MUST include the RFC5321.MailFrom domain!";
    };
    return 1;
};

1;
# ABSTRACT: Perl implementation of DMARC
__END__
sub {}  # for vim automatic code folding

=head1 SYNOPSIS

DMARC: Domain-based Message Authentication, Reporting and Conformance

=head1 DESCRIPTION

This module is a suite of tools for implementing DMARC. It adheres very tightly to the 2013 DMARC draft, intending to implement every MUST and every SHOULD.

This module can be used...

=over 4

by MTAs and filtering tools such as SpamAssassin to validate that incoming messages are aligned with the purported senders policies.

by an email sender that wishes to receive DMARC reports from other mail servers.

=back

When a message arrives via SMTP, the MTA or filtering application can pass in a small amount of metadata about the connection (envelope details, SPF results, and DKIM results) to Mail::DMARC. When the B<validate> method is called, the Mail::DMARC will determine if:

 a. the header_from domain exists
 b. the header_from domain publishes a DMARC policy
 c. if not, end processing
 d. does the message conform to the published policy?
 e. did the policy request reporting? If so, save details.

The validation results are stored in a L<Mail::DMARC::Result> object. Example inspection of a result object is shown in HOW TO USE. If a report was requested, it was saved via L<Mail::DMARC::Report::Store>. A SQL implementation is provided and tested with SQLite and MySQL. ANSI SQL queries syntax is preferred, making it straight forward to extend to other RDBMS.

=head1 HOW TO USE

 my $dmarc = Mail::DMARC->new( "see L<new|#new> for required args");
 my $result = $dmarc->verify();

 if ( $result->result eq 'pass' ) {
     ...continue normal processing...
     return;
 };

 # any result that did not pass is a fail. Now for disposition

 if ( $result->evalated->disposition eq 'reject' ) {
     ...treat the sender to a 550 ...
 };
 if ( $result->evalated->disposition eq 'quarantine' ) {
     ...assign a bunch of spam points...
 };
 if ( $result->evalated->disposition eq 'none' ) {
     ...continue normal processing...
 };

There is more information available in the $result object. See L<Mail::DMARC::Result> for complete details.

=head1 CLASSES

L<Mail::DMARC> - the perl interface for DMARC

L<Mail::DMARC::Policy> - a DMARC policy

L<Mail::DMARC::PurePerl> - Pure Perl implementation of DMARC

L<Mail::DMARC::Result> - the results of applying policy

L<Mail::DMARC::Report> - Reporting: the R in DMARC

=over 4

L<Mail::DMARC::Report::Send> - send reports via SMTP & HTTP

L<Mail::DMARC::Report::Receive> - receive and store reports from email, HTTP

L<Mail::DMARC::Report::Store> - a persistent data store for aggregate reports

L<Mail::DMARC::Report::View> - CLI and CGI methods for viewing reports

=back

L<Mail::DMARC::libopendmarc|http://search.cpan.org/~shari/Mail-DMARC-opendmarc> - an XS implementation using libopendmarc

=head1 METHODS

=head2 new

Create an empty DMARC object. Then populate it and run the request:

    my $dmarc = Mail::DMARC->new;
    $dmarc->source_ip('192.0.1.1');
    $dmarc->envelope_to('recipient.example.com');
    $dmarc->envelope_from('sender.example.com');
    $dmarc->header_from('sender.example.com');
    $dmarc->dkim( $dkim_verifier );
    $dmarc->spf(
        domain => 'example.com',
        scope  => 'mfrom',
        result => 'pass',
            );
    my $result = $dmarc->verify();

Alternatively, you can pass in all the required parameters in one shot:

    my $dmarc = Mail::DMARC->new(
            source_ip     => '192.0.1.1',
            envelope_to   => 'example.com',
            envelope_from => 'cars4you.info',
            header_from   => 'yahoo.com',
            dkim          => $dkim_results,  # same format
            spf           => $spf_results,   # as previous example
            );
    my $result = $dmarc->verify();


=head2 source_ip

The remote IP that attempted sending the message. DMARC only uses this data for reporting to domains that request DMARC reports.

=head2 envelope_to

The domain portion of the RFC5321.RcptTo, (aka, the envelope recipient), and the bold portion in the following example:

=over 8

RCPT TO:<user@B<example.com>>

=back

=head2 envelope_from

The domain portion of the RFC5321.MailFrom, (aka, the envelope sender). That is the the bold portion in the following example:

=over 8

MAIL FROM:<user@B<example.com>>

=back

=head2 header_from

The domain portion of the RFC5322.From, aka, the From message header.

=over 8

From: Ultimate Vacation <sweepstakes@B<example.com>>

=back

You can instead pass in the entire From: header with header_from_raw.

=head2 header_from_raw

Retrieve the header_from domain by parsing it from a raw From field/header. The domain portion is extracted by L<get_dom_from_header|Mail::DMARC::PurePerl#get_dom_from_header>, which is fast, generally effective, but also rather crude. It has limits, so read the description.

=head2 dkim

The dkim method accepts an array reference. Each array element represents a DKIM signature in the message and consists of the 4 keys shown in this example:

    $dmarc->dkim( [
            {
                domain      => 'example.com',
                selector    => 'apr2013',
                result      => 'fail',
                human_result=> 'fail (body has been altered)',
            },
            {
                # 2nd signature, if present
            },
        ] );

If you used Mail::DKIM::Verifier to validate the message, just pass in the Mail::DKIM::Verifier object that processed the message:

    $dmarc->dkim( $dkim_verifier );

=head3 domain

The d= parameter in the signature

=head3 selector

The s= parameter in the signature

=head3 result

The validation results of this signature. One of: none, pass, fail, policy, neutral, temperror, or permerror

=head3 human result

Additional information about the DKIM result. This is comparable to Mail::DKIM::Verifier->result_detail.

=head2 spf

The spf method accepts a hashref or named arguments:

    $dmarc->spf(
        domain => 'example.com',
        scope  => 'mfrom',
        result => 'pass',
    );

The SPF domain and result are required for DMARC validation and the scope is used for reporting.

=head3 domain

The SPF checked domain

=head3 scope

The scope of the checked domain: mfrom, helo

=head3 result

The SPF result code: none, neutral, pass, fail, softfail, temperror, or permerror.

=head1 DESIGN & GOALS

=head2 Correct

The DMARC spec is lengthy and evolving, making correctness a moving target. In cases where correctness is ambiguous, options are generally provided.

=head2 Easy to use

The effectiveness of DMARC will improve significantly as adoption increases. Proving an implementation of DMARC that SMTP utilities like SpamAssassin, amavis, and qpsmtpd can consume will aid adoption.

=head2 Maintainable

Since DMARC is evolving, this implementation aims to be straight forward and dare I say, easy, to alter and extend. The programming style is primarily OO, which carries a small performance penalty but large dividends in maintainability.

When multiple options are available, such as when sending reports via SMTP or HTTP, calls are made to the parent Send class, which brokers the request. When storing reports, calls are made to the Store class, which dispatches to the SQL class. The idea is that if someone desired a data store other than the many provided by perl's DBI class, they could easily implement their own. If you do, please fork it on GitHub and share.

=head2 Fast

I have conducted no optimization nor benchmarking and I am not a High Performance Perl expert. If you deploy this in an environment where performance is not sufficient, please do submit patches that are aligned with these goals.

=head1 SEE ALSO

Mail::DMARC on GitHub: https://github.com/msimerson/mail-dmarc

Mar 13, 2013 Draft: http://tools.ietf.org/html/draft-kucherawy-dmarc-base-00

Mar 30, 2012 Draft: http://www.dmarc.org/draft-dmarc-base-00-02.txt

=head1 HISTORY

The daddy of this perl module was a DMARC module for the qpsmtpd MTA.

Qpsmtpd plugin: https://github.com/qpsmtpd-dev/qpsmtpd-dev/blob/master/plugins/dmarc

=cut
