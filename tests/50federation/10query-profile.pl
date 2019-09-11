## This test often fails when run via haproxy on slower machines. See
#    https://github.com/matrix-org/sytest/issues/362
#  for more information.

test "Outbound federation can query profile data",
   requires => [ $main::INBOUND_SERVER, $main::SPYGLASS_USER,
                qw( can_get_displayname )],

   check => sub {
      my ( $inbound_server, $user ) = @_;

      my $local_server_name = $inbound_server->server_name;

      require_stub $inbound_server->await_request_query_profile( "\@user:$local_server_name" )
         ->on_done( sub {
            my ( $req ) = @_;

            $req->respond_json( {
               displayname => "The displayname of \@user:$local_server_name",
               avatar_url  => "",
            } );
         });

      do_request_json_for( $user,
         method => "GET",
         uri    => "/r0/profile/\@user:$local_server_name/displayname",
      )->then( sub {
         my ( $body ) = @_;
         log_if_fail "Query response", $body;

         assert_json_keys( $body, qw( displayname ));

         $body->{displayname} eq "The displayname of \@user:$local_server_name" or
            die "Displayname not as expected";

         Future->done(1);
      });
   };

my $dname = "Displayname Set For Federation Test";

test "Inbound federation can query profile data",
   requires => [ $main::OUTBOUND_CLIENT, local_user_fixture(),
                 qw( can_set_displayname )],

   do => sub {
      my ( $outbound_client, $user ) = @_;

      do_request_json_for( $user,
         method => "PUT",
         uri    => "/r0/profile/:user_id/displayname",

         content => {
            displayname => $dname,
         },
      )->then( sub {
         $outbound_client->do_request_json(
            method   => "GET",
            hostname => $user->server_name,
            uri      => "/v1/query/profile",

            params => {
               user_id => $user->user_id,
               field   => "displayname",
            }
         )
      })->then( sub {
         my ( $body ) = @_;
         log_if_fail "Query response", $body;

         assert_json_keys( $body, qw( displayname ));

         $body->{displayname} eq $dname or
            die "Expected displayname to be '$dname'";

         Future->done(1);
      });
   };
