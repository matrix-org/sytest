push our @EXPORT, qw( matrix_register_sync_user );

my $counter = 0;

sub matrix_register_sync_user {
    my ( $http ) = @_;
    my $user_id = "31sync_user_$counter";
    $counter += 1;
    matrix_register_user( $http, $user_id, with_events => 0);
}
