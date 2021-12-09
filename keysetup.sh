aws ssm get-parameter --name /bastion/default/private-key --with-decryption --output text --query Parameter.Value > ~/.ssh/id_rsa
chmod 400 ~/.ssh/id_rsa
