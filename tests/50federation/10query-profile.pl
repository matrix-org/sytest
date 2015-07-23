local *SyTest::Federation::Server::on_request_federation_v1_query_profile = sub {
   my $self = shift;
   my ( $req ) = @_;

   my %params = $req->as_http_request->uri->query_form;

   Future->done( {
      displayname => "The displayname of $params{user_id}",
      avatar_url  => "",
   } );
};

test "Outbound federation can query profile data",
   requires => [qw( do_request_json local_server_name
                    can_get_displayname )],

   check => sub {
      my ( $do_request_json, $local_server_name ) = @_;

      $do_request_json->(
         method => "GET",
         uri    => "/profile/\@user:$local_server_name/displayname",
      )->then( sub {
         my ( $body ) = @_;
         log_if_fail "Query response", $body;

         require_json_keys( $body, qw( displayname ));

         $body->{displayname} eq "The displayname of \@user:$local_server_name" or
            die "Displayname not as expected";

         Future->done(1);
      });
   };

my $dname = "Displayname Set For Federation Test";

test "Inbound federation can query profile data",
   requires => [qw( outbound_client do_request_json user
                    can_set_displayname )],

   do => sub {
      my ( $outbound_client, $do_request_json, $user ) = @_;

      $do_request_json->(
         method => "PUT",
         uri    => "/profile/:user_id/displayname",

         content => {
            displayname => $dname,
         },
      )->then( sub {
         $outbound_client->do_request_json(
            method => "GET",
            uri    => "/query/profile",

            params => {
               user_id => $user->user_id,
               field   => "displayname",
            }
         )
      })->then( sub {
         my ( $body ) = @_;
         log_if_fail "Query response", $body;

         require_json_keys( $body, qw( displayname ));

         $body->{displayname} eq $dname or
            die "Expected displayname to be '$dname'";

         Future->done(1);
      });
   };
