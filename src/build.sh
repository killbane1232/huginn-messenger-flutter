cd ~/git/huginn-messenger
go build -o huginn-messenger .
mkdir ./test_dir
mkdir ./test_dir/alice
mkdir ./test_dir/bob
mkdir ./test_dir/charley
cp huginn-messenger ./test_dir/alice/huginn
cp huginn-messenger ./test_dir/bob/huginn
cp huginn-messenger ./test_dir/charley/huginn
