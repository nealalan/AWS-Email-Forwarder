
idents=$(aws ses list-identities --query 'Identities' --output text --profile neonaluminum)

for ident in $idents; do
  aws ses get-identity-verification-attributes --identities $ident --output table --profile neonaluminum
done