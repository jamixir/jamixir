use rustler::{Encoder, Env, NifResult, Term};
// use reed_solomon::Decoder as ReedSolomonDecoder;
// mod test_from_json;

#[rustler::nif]
fn encode(data: Vec<u8>) -> NifResult<Vec<u8>> {
    // let rs = ReedSolomonEncoder::new(4);
    // let encoded = rs.encode(&data[..]);
    // let ecc_data = encoded.ecc();
    // Ok(ecc_data.into())
    Ok(vec![1, 2, 3])
}

// #[rustler::nif]
// fn decode(mut shards: Vec<Option<Vec<u8>>>) -> Vec<u8> {
//     let data_shards = shards.iter().filter(|x| x.is_some()).count();
//     let parity_shards = shards.len() - data_shards;

//     let rs = ReedSolomonDecoder::new(data_shards, parity_shards).unwrap();
//     rs.reconstruct(&mut shards).unwrap();

//     shards.into_iter().filter_map(|x| x).flatten().collect()
// }
rustler::init!("Elixir.ErasureCoding");