use SyTest::MailServer;
use Email::Address::XS;
use Email::MIME;
use List::UtilsBy qw( extract_first_by );


=head2 MAIL_SERVER_INFO

A fixture which starts a test SMTP server.

The result is a hash with the following members:

=over

=item host

hostname where this server can be reached

=item port

port where this server can be reached

=back

=cut

our $MAIL_SERVER_INFO = fixture(
   requires => [],
   setup => sub {
      my $mail_server = SyTest::MailServer->new(
         on_mail => \&_on_mail,
      );
      $loop->add( $mail_server );

      $mail_server->listen(
         host     => $BIND_HOST,
         service  => 0,
         socktype => 'stream',
      )->then( sub {
         my ( $listener ) = @_;
         my $sockport = $listener->read_handle->sockport;
         my $sockname = "$BIND_HOST:$sockport";

         $OUTPUT->diag( "Started test SMTP Server at $sockname" );
         Future->done({
            host => $BIND_HOST,
            # +0 because otherwise this comes back as a string, and perl is
            # awful
            port => $sockport + 0,
         });
      });
   },
);

push our @EXPORT, qw( MAIL_SERVER_INFO );

struct MailAwaiter => [qw( future rcpt_match )];

my @pending_awaiters;

sub _on_mail {
   my ( undef, $from, $to, $data ) = @_;

   if( $CLIENT_LOG ) {
      my $green = -t STDOUT ? "\e[1;32m" : "";
      my $reset = -t STDOUT ? "\e[m" : "";
      print "${green}Received mail${reset} from $from to $to:\n";
      print "  $_\n" for split m/\n/, $data;
      print "-- \n";
   }

   $to = Email::Address::XS->parse( $to )->address;
   $from = Email::Address::XS->parse( $from )->address;
   my $email = Email::MIME->new( $data );

   my $awaiter = extract_first_by {
      return $to eq $_->rcpt_match;
   } @pending_awaiters;

   if( $awaiter ) {
      $awaiter->future->done( $from, $email );
   } else {
      warn "Received spurious email from $from to $to\n";
   }
}

=head2 await_email_to

   await_email( $rcpt )->then( sub {
       my ( $from, $email ) = @_;
       print $email->body;
   });

<$email> is an C<Email::MIME> instance.

=cut

sub await_email_to {
   my ( $rcpt, %args ) = @_;
   my $timeout = $args{timeout} // 10;

   my $f = $loop->new_future;
   my $awaiter = MailAwaiter( $f, $rcpt );
   push @pending_awaiters, $awaiter;

   $f->on_cancel( sub {
      extract_first_by { $_ == $awaiter } @pending_awaiters;
   });

   return Future->wait_any(
      $f,
      delay( $timeout )->then_fail( "Timed out waiting for email" ),
   );
}

push @EXPORT, qw( await_email_to );
