use ed25519_zebra::{Signature, VerificationKey, VerificationKeyBytes};
use rustler::{Atom, Binary, Error, NifResult};

mod atoms {
    rustler::atoms! {
        ok,
        error,
        invalid_signature,
        invalid_public_key,
        invalid_signature_length,
        invalid_public_key_length,
    }
}

rustler::init!("Elixir.Util.Crypto.Ed25519Zip215");

/// Verify an Ed25519 signature using ZIP215 rules
///
/// This implementation:
/// - Uses the cofactor-8 verification equation
/// - Accepts non-canonical point encodings
/// - Requires canonical scalar encoding (s < q)
/// - Is batch-verification compatible
#[rustler::nif]
fn verify(signature: Binary, message: Binary, public_key: Binary) -> NifResult<Atom> {
    // Check lengths
    if signature.len() != 64 {
        return Ok(atoms::invalid_signature_length());
    }

    if public_key.len() != 32 {
        return Ok(atoms::invalid_public_key_length());
    }

    // Parse signature (64 bytes: R || s)
    let sig = match Signature::try_from(signature.as_slice()) {
        Ok(s) => s,
        Err(_) => return Ok(atoms::invalid_signature()),
    };

    // Parse public key (32 bytes)
    let pk_bytes = VerificationKeyBytes::try_from(public_key.as_slice())
        .map_err(|_| Error::Term(Box::new(atoms::invalid_public_key())))?;

    let pk = match VerificationKey::try_from(pk_bytes) {
        Ok(k) => k,
        Err(_) => return Ok(atoms::invalid_public_key()),
    };

    // Verify signature using ZIP215 rules
    match pk.verify(&sig, message.as_slice()) {
        Ok(_) => Ok(atoms::ok()),
        Err(_) => Ok(atoms::error()),
    }
}

/// Batch verify multiple Ed25519 signatures using ZIP215 rules
///
/// Batch verification is 2-3x faster than individual verification
/// and is only safe with ZIP215 compliance.
#[rustler::nif]
fn batch_verify(
    items: Vec<(Binary, Binary, Binary)>, // Vec<(signature, message, public_key)>
) -> NifResult<Atom> {
    use ed25519_zebra::batch;

    if items.is_empty() {
        return Ok(atoms::ok());
    }

    // Create a batch verifier
    let mut verifier = batch::Verifier::new();

    // Add all items to the batch
    for (sig_bin, msg_bin, pk_bin) in items {
        // Check lengths
        if sig_bin.len() != 64 || pk_bin.len() != 32 {
            return Ok(atoms::error());
        }

        // Parse signature
        let sig = match Signature::try_from(sig_bin.as_slice()) {
            Ok(s) => s,
            Err(_) => return Ok(atoms::invalid_signature()),
        };

        // Parse public key bytes (don't convert to VerificationKey yet)
        let pk_bytes = match VerificationKeyBytes::try_from(pk_bin.as_slice()) {
            Ok(b) => b,
            Err(_) => return Ok(atoms::invalid_public_key()),
        };

        // Clone message data since we need owned data for the verifier
        let msg_owned = msg_bin.as_slice();

        // Add to batch using Item::from with VerificationKeyBytes
        verifier.queue(batch::Item::from((pk_bytes, sig, msg_owned)));
    }

    // Perform batch verification
    match verifier.verify(rand::thread_rng()) {
        Ok(_) => Ok(atoms::ok()),
        Err(_) => Ok(atoms::error()),
    }
}
