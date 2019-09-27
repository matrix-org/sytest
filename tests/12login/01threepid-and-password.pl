my $password = "my secure password";

=head2 validate_email

   validate_email(
      $http, $address, $id_server, $path,
   )->then( sub {
      my ( $sid, $client_secret ) = @_;
   });

Runs through a `.../requestToken` flow specified by $path for verifying that an email address
belongs to the user. Doesn't add the address to the account.

Returns the session id and client secret which can then be used for binding the address.

=cut

sub validate_email {
   my ( $http, $address, $id_server, $path ) = @_;

   # fixme: synapse screws up the escaping of non-alpha chars.
   my $client_secret = join "", map { chr 65 + rand 26 } 1 .. 20;

   my $sid;

   return Future->needs_all(
      $http->do_request_json(
         method => "POST",
         uri    => $path,
         content => {
            client_secret   => $client_secret,
            email           => $address,
            send_attempt    => 1,
            id_server       => $id_server->name,
            id_access_token => $id_server->get_access_token(),
         },
      )->then( sub {
         my ( $resp ) = @_;
         log_if_fail "requestToken response", $resp;

         $sid = $resp->{sid};
         Future->done;
      }),

      # depending on the server under test, we should expect either a callout to
      # our test ID server, or an email from the homeserver.
      #
      Future->wait_any(
         await_and_confirm_email( $address, $http ),
         await_id_validation( $id_server, $address ),
      ),
   )->then( sub {
      Future->done( $sid, $client_secret );
   });
}
push our @EXPORT, qw( validate_email );

# wait for a call to /requestToken on the test IS, and act as if the
# email has been validated.
sub await_and_confirm_email {
   my ( $address, $http ) = @_;

   my $confirm_uri;

   return await_email_to( $address )->then( sub {
      my ( $from, $email ) = @_;
      log_if_fail "got email from $from";

      $email->walk_parts( sub {
         my ( $part ) = @_;
         return if $part->subparts; # multipart
         if ( $part->content_type =~ m[text/plain]i ) {
            my $body = $part->body;
            log_if_fail "got email body", $body;

            unless( $body =~ /(http\S*)/ ) {
               die "confirmation URI not found in email body";
            }

            $confirm_uri = $1;
         }
      });

      # do an http hit on the confirmation url
      $http->do_request(
         method   => "GET",
         full_uri => $confirm_uri,
      );
   });
}

sub await_id_validation {
   my ( $id_server, $address ) = @_;

   $id_server->await_request(
      path=>"/_matrix/identity/api/v1/validate/email/requestToken",
   )->then( sub {
      my ( $req ) = @_;
      my $body = $req->body_from_json;

      log_if_fail "ID server /requestToken request", $body;
      assert_eq( $body->{email}, $address );
      my $sid = $id_server->validate_identity( 'email', $address, $body->{client_secret} );
      $req->respond_json({
         sid => $sid,
      });
      Future->done();
   });
}

=head2 add_email_for_user

   add_email_for_user(
      $user, $address, $id_server, %params
   );

Add the given email address to the homeserver account, including the
verfication steps.

=cut

sub add_email_for_user {
   my ( $user, $address, $id_server, %params ) = @_;

   my $id_access_token = $id_server->get_access_token();

   # start by requesting an email validation.
   validate_email(
      $user->http, $address, $id_server, "/r0/account/3pid/email/requestToken",
   )->then( sub {
      my ( $sid, $client_secret ) = @_;

      # now tell the HS to add the 3pid
      do_request_json_for( $user,
         method => "POST",
         uri    => "/r0/account/3pid",
         content => {
            three_pid_creds => {
               id_server       => $id_server->name,
               id_access_token => $id_access_token,
               sid             => $sid,
               client_secret   => $client_secret,
            },
         },
      );
   });
}

push @EXPORT, qw( add_email_for_user );

test "Can login with 3pid and password using m.login.password",
   requires => [ local_user_fixture( password => $password ), id_server_fixture() ],

   check => sub {
      my ( $user, $id_server ) = @_;

      my $http = $user->http;

      my $address = 'bob@example.com';

      add_email_for_user( $user, $address, $id_server )
      ->then( sub {
         $http->do_request_json(
            method => "POST",
            uri    => "/r0/login",

            content => {
               type     => "m.login.password",
               medium   => 'email',
               address  => $address,
               password => $password,
            }
         );
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( access_token home_server ));

         assert_eq( $body->{home_server}, $http->server_name,
            'Response home_server' );

         Future->done(1);
      });
   };
