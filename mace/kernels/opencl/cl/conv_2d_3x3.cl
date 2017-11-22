#include <common.h>

VEC_DATA_TYPE(DATA_TYPE,4) conv1x3_s1(const DATA_TYPE *input_ptr,
                                      const DATA_TYPE *filter_ptr) {
  VEC_DATA_TYPE(DATA_TYPE,4) row0 = vload4(0, input_ptr);
  VEC_DATA_TYPE(DATA_TYPE,2) input1 = vload2(0, input_ptr+4);
  VEC_DATA_TYPE(DATA_TYPE,4) row1 = (VEC_DATA_TYPE(DATA_TYPE,4))(row0.s123, input1.s0);
  VEC_DATA_TYPE(DATA_TYPE,4) row2 = (VEC_DATA_TYPE(DATA_TYPE,4))(row0.s23, input1.s01);
  VEC_DATA_TYPE(DATA_TYPE,3) filter_values = vload3(0, filter_ptr);
  return (VEC_DATA_TYPE(DATA_TYPE,4))filter_values.s0 * row0 +
         (VEC_DATA_TYPE(DATA_TYPE,4))filter_values.s1 * row1 +
         (VEC_DATA_TYPE(DATA_TYPE,4))filter_values.s2 * row2;
}

VEC_DATA_TYPE(DATA_TYPE,4) conv1x3_s2(const DATA_TYPE *input_ptr,
                                      const DATA_TYPE *filter_ptr) {
  VEC_DATA_TYPE(DATA_TYPE,8) input = vload8(0, input_ptr);
  VEC_DATA_TYPE(DATA_TYPE,4) row0 = input.even;
  VEC_DATA_TYPE(DATA_TYPE,4) row1 = input.odd;
  VEC_DATA_TYPE(DATA_TYPE,4) row2 = (VEC_DATA_TYPE(DATA_TYPE,4))(row0.s123, input_ptr[8]);
  VEC_DATA_TYPE(DATA_TYPE,3) filter_values = vload3(0, filter_ptr);
  return (VEC_DATA_TYPE(DATA_TYPE,4))filter_values.s0 * row0 +
         (VEC_DATA_TYPE(DATA_TYPE,4))filter_values.s1 * row1 +
         (VEC_DATA_TYPE(DATA_TYPE,4))filter_values.s2 * row2;
}

// Supported data type: half/float
DATA_TYPE conv3x3(const DATA_TYPE *input_ptr,
                  const DATA_TYPE *filter_ptr,
                  const int row_width) {
  VEC_DATA_TYPE(DATA_TYPE,3) input_value = vload3(0, input_ptr);
  VEC_DATA_TYPE(DATA_TYPE,3) filter_value = vload3(0, filter_ptr);
  VEC_DATA_TYPE(DATA_TYPE,3) res = input_value * filter_value;
  input_ptr += row_width;
  input_value = vload3(0, input_ptr);
  filter_value = vload3(1, filter_ptr);
  res += input_value * filter_value;
  input_ptr += row_width;
  input_value = vload3(0, input_ptr);
  filter_value = vload3(2, filter_ptr);
  res += input_value * filter_value;

  return res.s0 + res.s1 + res.s2;
}

void kernel conv_2d_3x3(global const DATA_TYPE *input,
                        global const DATA_TYPE *filter,
#ifdef BIAS
                        global const DATA_TYPE *bias,
#endif
                        global DATA_TYPE *output,
                        private const int in_chan_num,
                        private const int out_chan_num,
                        private const int in_height,
                        private const int in_width,
                        private const int out_height,
                        private const int out_width) {
  int batch = get_global_id(0);
  int out_chan_blk = get_global_id(1);
  int out_pixel_blk = get_global_id(2);

  const int in_pixel = in_height * in_width;
  const int out_pixel = out_height * out_width;

  const int round_out_width = (out_width + 3) / 4;
  const int out_pixel_height = out_pixel_blk / round_out_width;
  const int out_pixel_width = out_pixel_blk % round_out_width;

  const int out_chan_begin = out_chan_blk * 4;
  const int out_chan_end = min(out_chan_begin + 4, out_chan_num);
  const int out_pixel_begin = out_pixel_height * out_width + out_pixel_width * 4;
  const int out_pixel_end = min(out_pixel_begin + 4, (out_pixel_height + 1) * out_width);
#ifdef STRIDE_1
  const int stride = 1;
#else
  const int stride = 2;
#endif
  const int in_pixel_begin = out_pixel_height * stride * in_width + out_pixel_width * stride * 4;

  const int in_offset = batch * in_chan_num * in_pixel;
  const int out_offset = batch * out_chan_num * out_pixel;
  const DATA_TYPE *input_base = input + in_offset + in_pixel_begin;
  DATA_TYPE *output_base = output + out_offset + out_pixel_begin;

  const int pixels = out_pixel_end - out_pixel_begin;

  for (int i = out_chan_begin; i < out_chan_end; ++i) {
    DATA_TYPE *output_ptr = output_base + i * out_pixel;
    const DATA_TYPE *filter_base = filter + i * in_chan_num * 9;
    if (pixels == 4) {
#ifdef BIAS
      VEC_DATA_TYPE(DATA_TYPE, 4) res = (VEC_DATA_TYPE(DATA_TYPE, 4))bias[i];
#else
      VEC_DATA_TYPE(DATA_TYPE, 4) res = 0;
#endif

      for (int in_chan_idx = 0; in_chan_idx < in_chan_num; ++in_chan_idx) {
        const DATA_TYPE *input_ptr = input_base + in_chan_idx * in_pixel;
        const DATA_TYPE *filter_ptr = filter_base + in_chan_idx * 9;
#ifdef STRIDE_1
        res += conv1x3_s1(input_ptr + 0 * in_width, filter_ptr + 0 * 3);
        res += conv1x3_s1(input_ptr + 1 * in_width, filter_ptr + 1 * 3);
        res += conv1x3_s1(input_ptr + 2 * in_width, filter_ptr + 2 * 3);
#else
        res += conv1x3_s2(input_ptr + 0 * in_width, filter_ptr + 0 * 3);
        res += conv1x3_s2(input_ptr + 1 * in_width, filter_ptr + 1 * 3);
        res += conv1x3_s2(input_ptr + 2 * in_width, filter_ptr + 2 * 3);
#endif
      }
      vstore4(res, 0, output_ptr);
    } else {
      for (int p = 0; p < pixels; ++p) {
#ifdef BIAS
        DATA_TYPE res = bias[i];
#else
        DATA_TYPE res = 0;
#endif
        for (uint in_chan_idx = 0; in_chan_idx < in_chan_num; ++in_chan_idx) {
          const DATA_TYPE *input_ptr = input_base + in_chan_idx * in_pixel + p * stride;
          const DATA_TYPE *filter_ptr = filter_base + in_chan_idx * 9;
          res += conv3x3(input_ptr, filter_ptr, in_width);
        }
        output_ptr[p] = res;
      }
    }
  }
}