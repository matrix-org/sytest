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
