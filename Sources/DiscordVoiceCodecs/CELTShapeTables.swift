/* Copyright (c) 2007-2008 CSIRO
   Copyright (c) 2007-2009 Xiph.Org Foundation
   Written by Jean-Marc Valin */
/*
   Redistribution and use in source and binary forms, with or without
   modification, are permitted provided that the following conditions
   are met:

   - Redistributions of source code must retain the above copyright
   notice, this list of conditions and the following disclaimer.

   - Redistributions in binary form must reproduce the above copyright
   notice, this list of conditions and the following disclaimer in the
   documentation and/or other materials provided with the distribution.

   THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
   ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
   LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
   A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER
   OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
   EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
   PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
   PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
   LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
   NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
   SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

/// Ordinary-mode pulse cache transcribed from libopus 1.6.1; no runtime source loading.
enum CELTShapeTables {
    static let indices: [Int] = [
        -1, -1, -1, -1, -1, -1, -1, -1, 0, 0, 0, 0, 41, 41, 41, 82,
        82, 123, 164, 200, 222, 0, 0, 0, 0, 0, 0, 0, 0, 41, 41, 41,
        41, 123, 123, 123, 164, 164, 240, 266, 283, 295, 41, 41, 41, 41, 41, 41,
        41, 41, 123, 123, 123, 123, 240, 240, 240, 266, 266, 305, 318, 328, 336, 123,
        123, 123, 123, 123, 123, 123, 123, 240, 240, 240, 240, 305, 305, 305, 318, 318,
        343, 351, 358, 364, 240, 240, 240, 240, 240, 240, 240, 240, 305, 305, 305, 305,
        343, 343, 343, 351, 351, 370, 376, 382, 387,
    ]
    static let bits: [Int] = [
        40, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7,
        7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7,
        7, 7, 7, 7, 7, 7, 7, 7, 7, 40, 15, 23, 28, 31, 34, 36,
        38, 39, 41, 42, 43, 44, 45, 46, 47, 47, 49, 50, 51, 52, 53, 54,
        55, 55, 57, 58, 59, 60, 61, 62, 63, 63, 65, 66, 67, 68, 69, 70,
        71, 71, 40, 20, 33, 41, 48, 53, 57, 61, 64, 66, 69, 71, 73, 75,
        76, 78, 80, 82, 85, 87, 89, 91, 92, 94, 96, 98, 101, 103, 105, 107,
        108, 110, 112, 114, 117, 119, 121, 123, 124, 126, 128, 40, 23, 39, 51, 60,
        67, 73, 79, 83, 87, 91, 94, 97, 100, 102, 105, 107, 111, 115, 118, 121,
        124, 126, 129, 131, 135, 139, 142, 145, 148, 150, 153, 155, 159, 163, 166, 169,
        172, 174, 177, 179, 35, 28, 49, 65, 78, 89, 99, 107, 114, 120, 126, 132,
        136, 141, 145, 149, 153, 159, 165, 171, 176, 180, 185, 189, 192, 199, 205, 211,
        216, 220, 225, 229, 232, 239, 245, 251, 21, 33, 58, 79, 97, 112, 125, 137,
        148, 157, 166, 174, 182, 189, 195, 201, 207, 217, 227, 235, 243, 251, 17, 35,
        63, 86, 106, 123, 139, 152, 165, 177, 187, 197, 206, 214, 222, 230, 237, 250,
        25, 31, 55, 75, 91, 105, 117, 128, 138, 146, 154, 161, 168, 174, 180, 185,
        190, 200, 208, 215, 222, 229, 235, 240, 245, 255, 16, 36, 65, 89, 110, 128,
        144, 159, 173, 185, 196, 207, 217, 226, 234, 242, 250, 11, 41, 74, 103, 128,
        151, 172, 191, 209, 225, 241, 255, 9, 43, 79, 110, 138, 163, 186, 207, 227,
        246, 12, 39, 71, 99, 123, 144, 164, 182, 198, 214, 228, 241, 253, 9, 44,
        81, 113, 142, 168, 192, 214, 235, 255, 7, 49, 90, 127, 160, 191, 220, 247,
        6, 51, 95, 134, 170, 203, 234, 7, 47, 87, 123, 155, 184, 212, 237, 6,
        52, 97, 137, 174, 208, 240, 5, 57, 106, 151, 192, 231, 5, 59, 111, 158,
        202, 243, 5, 55, 103, 147, 187, 224, 5, 60, 113, 161, 206, 248, 4, 65,
        122, 175, 224, 4, 67, 127, 182, 234,
    ]
}
