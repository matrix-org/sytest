# How many more users do we want?
my $LOCAL_USERS = 2;

prepare "More local users",
   requires => [qw( first_http_client can_register )],

   do => sub {
      my ( $http ) = @_;

      Future->needs_all( map {
         my $uid = "09more-users-$_";

         $http->do_request_json(
            method => "POST",
            uri    => "/register",

            content => {
               type     => "m.login.password",
               user     => $uid,
               password => "an0th3r s3kr1t",
            },
         )->then( sub {
            my ( $body ) = @_;
            my ( $user_id, $access_token ) = @{$body}{qw( user_id access_token )};

            $http->do_request_json(
               method => "GET",
               uri    => "/events",
               params => { access_token => $access_token, timeout => 0 },
            )->then( sub {
               my ( $body ) = @_;

               Future->done( User( $user_id, $access_token, $body->{end} ) );
            });
         });
      } 1 .. $LOCAL_USERS
      )->then( sub {
         my @users = @_;

         provide more_users => \@users;

         # A variant of GET_new_events for User() structs
         provide GET_new_events_for_user => sub {
            my ( $user, $filter ) = @_;
            $filter = qr/^\Q$filter\E$/ if defined $filter and not ref $filter;

            $http->do_request_json(
               method => "GET",
               uri    => "/events",
               params => {
                  access_token => $user->access_token,
                  from         => $user->eventstream_token,
                  timeout      => 10000,
               }
            )->then( sub {
               my ( $body ) = @_;
               $user->eventstream_token = $body->{end};

               if( defined $filter ) {
                  Future->done( grep { $_->{type} =~ $filter } @{ $body->{chunk} } );
               }
               else {
                  Future->done( @{ $body->{chunk} } );
               }
            });
         };

         Future->done();
      })
   };
