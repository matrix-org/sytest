use utf8;
use JSON qw( decode_json );
use URI;

# See also 10apidoc/01register.pl

# Generate a client_secret for 3pid operations
sub gen_client_secret {
   # fixme: synapse screws up the escaping of non-alpha chars.
   return join "", map { chr 65 + rand 26 } 1 .. 20;
}

=head2 validate_email

   validate_email(
      $http, $address,
      id_server => $id_server,
      path => "/r0/account/3pid/email/requestToken",
   )->then( sub {
      my ( $sid, $client_secret ) = @_;
   });

Runs through a `.../requestToken` flow specified by $path for verifying that an email address
belongs to the user. Doesn't add the address to the account.

Returns the session id and client secret which can then be used for binding the address.

=cut

sub validate_email {
   my ( $http, $address, %params ) = @_;

   my $client_secret = gen_client_secret();
   my $sid;

   return Future->needs_all(
      await_confirmation_email( $address, $http ),

      $http->do_request_json(
         method => "POST",
         uri    => $params{path},
         content => {
            client_secret   => $client_secret,
            email           => $address,
            send_attempt    => 1,
            id_server       => $params{id_server}->name,
            id_access_token => $params{id_server}->get_access_token(),
         },
      )->then( sub {
         my ( $resp ) = @_;
         log_if_fail "requestToken response", $resp;

         $sid = $resp->{sid};
         Future->done;
      }),
   )->then( sub {
      my ( $confirm_uri ) = @_;

      log_if_fail "Confirm uri", $confirm_uri;

      # do an http hit on the confirmation url
      $http->do_request(
         method   => "GET",
         full_uri => $confirm_uri,
      );
   })->then( sub {
      Future->done( $sid, $client_secret );
   });
}
push our @EXPORT, qw( validate_email );


=head2 validate_email_on_id_server

   validate_email_on_id_server(
      $http, $address,
      id_server => $id_server,
      path => "/r0/account/3pid/email/requestToken",
   )->then( sub {
      my ( $sid, $client_secret ) = @_;
   });

Runs through a `.../requestToken` flow specified by $path for verifying that an email address
belongs to the user. Doesn't add the address to the account. It does not submit token as
validate_email does, but expects that mock identity server will validate email immediately.

Returns the session id and client secret which can then be used for binding the address.

=cut

sub validate_email_on_id_server {
   my ( $http, $address, %params ) = @_;

   my $client_secret = gen_client_secret();
   my $sid;

   return Future->needs_all(
      await_id_validation_email( $params{id_server}, $address),

      $http->do_request_json(
         method => "POST",
         uri    => $params{path},
         content => {
            client_secret   => $client_secret,
            email           => $address,
            send_attempt    => 1,
            id_server       => $params{id_server}->name,
            id_access_token => $params{id_server}->get_access_token(),
         },
      )->then( sub {
         my ( $resp ) = @_;
         log_if_fail "requestToken response", $resp;

         $sid = $resp->{sid};
         Future->done;
      }),
   )->then( sub {
      Future->done( $sid, $client_secret );
   });
}
push our @EXPORT, qw( validate_email_on_id_server );

=head2 validate_msisdn

   validate_msisdn(
      $http, $phone_number, $country_code,
      id_server => $id_server,
      path => "/r0/account/3pid/msisdn/requestToken",
   )->then( sub {
      my ( $sid, $client_secret ) = @_;
   });

Runs through a `.../requestToken` flow specified by $path for verifying that a phone number
belongs to the user. Doesn't add the number to the account.

Returns the session id and client secret which can then be used for binding the phone number.

=cut

sub validate_msisdn {
   my ( $http, $phone_number, $country_code, %params ) = @_;

   my $client_secret = gen_client_secret();
   my $sid;
   my $id_server = $params{id_server};
   my $path = $params{path};

   return Future->needs_all(
      $http->do_request_json(
         method => "POST",
         uri    => $path,
         content => {
            client_secret   => $client_secret,
            phone_number    => $phone_number,
            country_code    => $country_code,
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

      # TODO: Test receiving SMS once Synapse has the ability to send them
      Future->wait_any(
         await_id_validation_msisdn( $id_server, $phone_number, $country_code ),
      ),
   )->then( sub {
      Future->done( $sid, $client_secret );
   });
}

# Wait for a confirmation email and return the confirmation URI.
sub await_confirmation_email {
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

      Future->done( $confirm_uri );
   });
}

# wait for a requestToken call to the built-in identity server
sub await_id_validation_email {
   my ( $id_server, $address ) = @_;

   $id_server->await_request(
      path=>"/_matrix/identity/api/v1/validate/email/requestToken",
   )->then( sub {
      my ( $req ) = @_;
      my $body = $req->body_from_json;

      log_if_fail "ID server email /requestToken request", $body;
      assert_eq( $body->{email}, $address );
      my $sid = $id_server->validate_identity("email", $address, $body->{client_secret} );
      $req->respond_json({
         sid => $sid,
      });
      Future->done();
   });
}

# wait for a requestToken call to the built-in identity server
sub await_id_validation_msisdn {
   my ( $id_server, $phone_number, $country_code ) = @_;

   $id_server->await_request(
      path=>"/_matrix/identity/api/v1/validate/msisdn/requestToken",
   )->then( sub {
      my ( $req ) = @_;
      my $body = $req->body_from_json;

      log_if_fail "ID server msisdn /requestToken request", $body;
      assert_eq( $body->{phone_number}, $phone_number );
      assert_eq( $body->{country_code}, $country_code );
      my $sid = $id_server->validate_msisdn(
         $phone_number, $country_code, $body->{client_secret}
      );
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
      $user->http, $address,
      id_server => $id_server,
      path => "/r0/account/3pid/email/requestToken",
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

# This test only tests the recaptcha validation stage, and not
# and actual registration. It also abuses the fact the Synapse
# permits validation of a recaptcha stage even if it's not actually
# required in any of the given auth flows.
multi_test "Register with a recaptcha",
   requires => [ $main::API_CLIENTS[0], localpart_fixture() ],

   do => sub {
      my ( $http, $localpart ) = @_;

      Future->needs_all(
         await_http_request( "/recaptcha/api/siteverify", sub {1} )
            ->SyTest::pass_on_done( "Got recaptcha verify request" )
         ->then( sub {
            my ( $request ) = @_;

            my $params = $request->body_from_form;

            $params->{secret} eq "sytest_recaptcha_private_key" or
               die "Bad secret";

            $params->{response} eq "sytest_captcha_response" or
               die "Bad response";

            $request->respond_json(
               { success => JSON::true },
            );

            Future->done(1);
         }),

         $http->do_request_json(
            method  => "POST",
            uri     => "/r0/register",
            content => {
               username => $localpart,
               password => "my secret",
               auth     => {
                  type     => "m.login.recaptcha",
                  response => "sytest_captcha_response",
               },
            },
         )->main::expect_http_4xx
         ->then( sub {
            my ( $response ) = @_;

            my $body = decode_json $response->content;

            log_if_fail "Body:", $body;

            assert_json_keys( $body, qw(completed) );
            assert_json_list( my $completed = $body->{completed} );

            @$completed == 1 or
               die "Expected one completed stage";

            $completed->[0] eq "m.login.recaptcha" or
               die "Expected to complete m.login.recaptcha";

            pass "Passed captcha validation";
            Future->done(1);
         }),
      )
   };

test "registration is idempotent, without username specified",
   requires => [ $main::API_CLIENTS[0] ],

   do => sub {
      my ( $http ) = @_;

      my $session;
      my $user_id;

      # Start a session
      $http->do_request_json(
         method => "POST",
         uri    => "/r0/register",

         content => {
            password => "s3kr1t",
         },
      )->main::expect_http_401->then( sub {
         my ( $response ) = @_;

         my $body = decode_json $response->content;

         assert_json_keys( $body, qw( session ));

         $session = $body->{session};

         # Now register a user
         $http->do_request_json(
            method => "POST",
            uri    => "/r0/register",

            content => {
               password => "s3kr1t",
               auth     => {
                  session => $session,
                  type    => "m.login.dummy",
               }
            },
         );
      })->then( sub {
         my ( $body ) = @_;

         # check that worked okay...
         assert_json_keys( $body, qw( user_id home_server access_token ));

         $user_id = $body->{user_id};

         # now try to register again with the same session
         $http->do_request_json(
            method => "POST",
            uri    => "/r0/register",

            content => {
               password => "s3kr1t",
               auth     => {
                  session => $session,
                  type    => "m.login.dummy",
               }
            },
         );
      })->then( sub {
         my ( $body ) = @_;

         # we should have got an equivalent response
         # (ie. success, and the same user id)
         assert_json_keys( $body, qw( user_id home_server access_token ));

         assert_eq( $body->{user_id}, $user_id );

         Future->done( 1 );
      });
   };

test "registration is idempotent, with username specified",
   requires => [ $main::API_CLIENTS[0], localpart_fixture() ],

   do => sub {
      my ( $http, $localpart ) = @_;

      my $session;

      # Start a session
      $http->do_request_json(
         method => "POST",
         uri    => "/r0/register",

         content => {
            username => $localpart,
            password => "s3kr1t",
         },
      )->main::expect_http_401->then( sub {
         my ( $response ) = @_;

         my $body = decode_json $response->content;

         assert_json_keys( $body, qw( session ));

         $session = $body->{session};

         # Now register a user
         $http->do_request_json(
            method => "POST",
            uri    => "/r0/register",

            content => {
               username => $localpart,
               password => "s3kr1t",
               auth     => {
                  session => $session,
                  type    => "m.login.dummy",
               }
            },
         );
      })->then( sub {
         my ( $body ) = @_;

         # check that worked okay...
         assert_json_keys( $body, qw( user_id home_server access_token ));

         # now try to register again with the same session
         $http->do_request_json(
            method => "POST",
            uri    => "/r0/register",

            content => {
               username => $localpart,
               password => "s3kr1t",
               auth     => {
                  session => $session,
                  type    => "m.login.dummy",
               }
            },
         );
      })->then( sub {
         my ( $body ) = @_;

         # we should have got an equivalent response
         # (ie. success, and the same user id)
         assert_json_keys( $body, qw( user_id home_server access_token ));

         my $actual_user_id = $body->{user_id};
         my $home_server = $body->{home_server};

         assert_eq( $actual_user_id, "\@$localpart:$home_server",
            "registered user ID" );

         Future->done( 1 );
      });
   };

test "registration remembers parameters",
   requires => [ $main::API_CLIENTS[0], localpart_fixture() ],

   do => sub {
      my ( $http, $localpart ) = @_;

      my $session;

      $http->do_request_json(
         method => "POST",
         uri    => "/r0/register",

         content => {
            username => $localpart,
            password => "s3kr1t",
            device_id => "xyzzy",
            initial_device_display_name => "display_name",
         },
      )->main::expect_http_401->then( sub {
         my ( $response ) = @_;

         my $body = decode_json $response->content;

         assert_json_keys( $body, qw( session ));

         $session = $body->{session};

         $http->do_request_json(
            method => "POST",
            uri    => "/r0/register",

            content => {
               auth     => {
                  session => $session,
                  type    => "m.login.dummy",
               }
            },
         );
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( user_id home_server access_token ));

         my $actual_user_id = $body->{user_id};
         my $home_server = $body->{home_server};

         assert_eq( $actual_user_id, "\@$localpart:$home_server",
            "registered user ID" );

         my $user = new_User(
            http          => $http,
            user_id       => $actual_user_id,
            device_id     => $body->{device_id},
            access_token  => $body->{access_token},
         );
         # check that the right device_id was registered
         matrix_get_device( $user, "xyzzy" );
      })->then( sub {
         my ( $device ) = @_;
         assert_eq( $device->{display_name}, "display_name");
         Future->done( 1 );
      });
   };

test "registration accepts non-ascii passwords",
   requires => [ $main::API_CLIENTS[0], localpart_fixture() ],

   do => sub {
      my ( $http, $localpart ) = @_;

      $http->do_request_json(
         method => "POST",
         uri    => "/r0/register",

         content => {
            username => $localpart,
            password => "übers3kr1t",
            device_id => "xyzzy",
            initial_device_display_name => "display_name",
         },
      )->main::expect_http_401->then( sub {
         my ( $response ) = @_;

         my $body = decode_json $response->content;

         assert_json_keys( $body, qw( session ));

         my $session = $body->{session};

         $http->do_request_json(
            method => "POST",
            uri    => "/r0/register",

            content => {
               auth     => {
                  session => $session,
                  type    => "m.login.dummy",
               }
            },
         );
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( user_id home_server access_token ));
         Future->done( 1 );
      });
   };

test "registration with inhibit_login inhibits login",
   requires => [ $main::API_CLIENTS[0], localpart_fixture() ],

   do => sub {
      my ( $http, $localpart ) = @_;

      my $session;

      $http->do_request_json(
         method => "POST",
         uri    => "/r0/register",

         content => {
            username => $localpart,
            password => "s3kr1t",
            inhibit_login => 1,
         },
      )->main::expect_http_401->then( sub {
         my ( $response ) = @_;

         my $body = decode_json $response->content;

         assert_json_keys( $body, qw( session ));

         $session = $body->{session};

         $http->do_request_json(
            method => "POST",
            uri    => "/r0/register",

            content => {
               auth     => {
                  session => $session,
                  type    => "m.login.dummy",
               }
            },
         );
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( user_id home_server ));
         foreach ( qw( device_id access_token )) {
            exists $body->{$_} and die "Got an unexpected a '$_' key";
         }

         my $actual_user_id = $body->{user_id};
         my $home_server = $body->{home_server};

         assert_eq( $actual_user_id, "\@$localpart:$home_server",
            "registered user ID" );

         Future->done( 1 );
      });
   };

test "User signups are forbidden from starting with '_'",
   requires => [ $main::API_CLIENTS[0] ],

   do => sub {
      my ( $http ) = @_;

      matrix_register_user( $http, "_badname_here" )
         ->main::expect_http_4xx;
   };

test "Can register using an email address",
   requires => [ $main::API_CLIENTS[0], localpart_fixture(), id_server_fixture() ],

   do => sub {
      my ( $http, $localpart, $id_server ) = @_;

      my $email_address = 'testemail@example.com';

      $http->do_request_json(
         method => "POST",
         uri    => "/r0/register",

         content => {
            username => $localpart,
            password => "noobers3kr1t",
            device_id => "xyzzy",
         },
      )->main::expect_http_401->then( sub {
         my ( $response ) = @_;

         my $body = decode_json $response->content;

         assert_json_keys( $body, qw( session flows ));

         log_if_fail "No single m.login.email.identity stage registration flow found", $body;

         # Check that one of the flows' stages contains an "m.login.email.identity" stage
         my $has_flow;
         foreach my $idx ( 0 .. $#{ $body->{flows} } ) {
            my $flow = $body->{flows}[$idx];
            my $stages = $flow->{stages} || [];

            $has_flow++ if
               @$stages == 1 && $stages->[0] eq "m.login.email.identity";
         }

         assert_eq( $has_flow, 1 );

         validate_email(
            $http,
            $email_address,
            id_server => $id_server,
            path => "/r0/register/email/requestToken",
         )->then( sub {
            my ( $sid_email, $client_secret ) = @_;

            # attempt to register with the 3pid
            $http->do_request_json(
               method => "POST",
               uri    => "/r0/register",
               content => {
                  auth => {
                     type           => "m.login.email.identity",
                     session        => $body->{session},
                     threepid_creds => {
                        sid           => $sid_email,
                        client_secret => $client_secret,
                     },
                  },
                  username  => $localpart,
                  password  => "noobers3kr1t",
                  device_id => "xyzzy",
               },
            )
         })
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( user_id home_server ) );
         Future->done( 1 );
      });
   };

test "Can register using an email address via identity server",
   requires => [ $main::API_CLIENTS[0], localpart_fixture(), id_server_fixture() ],

   do => sub {
      my ( $http, $localpart, $id_server ) = @_;

      my $email_address = 'testemail@example.com';

      $http->do_request_json(
         method => "POST",
         uri    => "/r0/register",

         content => {
            username => $localpart,
            password => "noobers3kr1t",
            device_id => "xyzzy",
         },
      )->main::expect_http_401->then( sub {
         my ( $response ) = @_;

         my $body = decode_json $response->content;

         assert_json_keys( $body, qw( session flows ));

         log_if_fail "First /register body", $body;

         # Check that one of the flows' stages contains an "m.login.email.identity" stage
         my $has_flow;
         foreach my $idx ( 0 .. $#{ $body->{flows} } ) {
            my $flow = $body->{flows}[$idx];
            my $stages = $flow->{stages} || [];

            $has_flow++ if
               @$stages == 1 && $stages->[0] eq "m.login.email.identity";
         }

         assert_eq( $has_flow, 1, "hasFlow" );

         validate_email_on_id_server(
            $http,
            $email_address,
            id_server => $id_server,
            path => "/r0/register/email/requestToken",
         )->then( sub {
            my ( $sid_email, $client_secret ) = @_;

            # attempt to register with the 3pid
            $http->do_request_json(
               method => "POST",
               uri    => "/r0/register",
               content => {
                  auth => {
                     type           => "m.login.email.identity",
                     session        => $body->{session},
                     threepidCreds => {
                        sid             => $sid_email,
                        client_secret   => $client_secret,
                        id_server       => $id_server->name,
                        id_access_token => "foobar",
                     },
                  },
                  username  => $localpart,
                  password  => "noobers3kr1t",
                  device_id => "xyzzy",
               },
            )
         })
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( user_id home_server ) );
         Future->done( 1 );
      });
   };
