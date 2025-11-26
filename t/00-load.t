use Test2::V0;

ok lives {
    require Jsonnet::XS;
    Jsonnet::XS->VERSION;
}, 'Jsonnet::XS loads';

done_testing;
