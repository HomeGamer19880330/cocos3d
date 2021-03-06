/*
 * CC3MultiTextureConfigurable.fsh
 *
 * cocos3d 2.0.0
 * Author: Bill Hollings
 * Copyright (c) 2011-2013 The Brenwill Workshop Ltd. All rights reserved.
 * http://www.brenwill.com
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 *
 * http://en.wikipedia.org/wiki/MIT_License
 */

/**
 * This fragment shader provides a general configurable shader that replicates much of the
 * functionality of the fixed-pipeline of OpenGL ES 1.1 when configuring and blending multiple
 * textures on a single model.
 *
 * If the alpha component of the fragment is lower than a specified level, the fragment is discarded.
 *
 * In order to reduce the number of uniform variables, this shader supports two texture units.
 * This can be increased by changing the MAX_TEXTURES macro definition below.
 *
 * CC3Texturable.vsh is the vertex shader paired with this fragment shader.
 *
 * The semantics of the variables in this shader can be mapped using a
 * CC3ShaderProgramSemanticsByVarName instance.
 *
 * When using this shader, be aware that the general nature and high-level of configurability
 * available with this shader means that it cannot be optimized to the same degree that a more
 * deliberately dedicated shader can be optimized, and will run substantially slower than a
 * bespoke shader. This shader may be used during early stages of development, but for optimal
 * performance, it is recommended that the application provide specialized shaders that have
 * been tuned and optimized to a specific needs of each model.
 */

// Increase this if more textures are desired.
#define MAX_TEXTURES			2

// Texture constants to support OpenGL ES 1.1 conformant multi-texturing.
#define k_GL_REPLACE                0x1E01
#define k_GL_MODULATE               0x2100
#define k_GL_DECAL                  0x2101
#define k_GL_BLEND                  0x0BE2
#define k_GL_ADD                    0x0104
#define k_GL_COMBINE                0x8570
#define k_GL_ADD_SIGNED             0x8574
#define k_GL_INTERPOLATE            0x8575
#define k_GL_SUBTRACT               0x84E7
#define k_GL_DOT3_RGB               0x86AE
#define k_GL_DOT3_RGBA              0x86AF
#define k_GL_TEXTURE                0x1702
#define k_GL_CONSTANT               0x8576
#define k_GL_PRIMARY_COLOR          0x8577
#define k_GL_PREVIOUS               0x8578

precision mediump float;

//-------------- UNIFORMS ----------------------

uniform bool		u_cc3VertexHasTangent;			/**< Whether the vertex tangent is available. */

uniform float		u_cc3MaterialMinimumDrawnAlpha;	/**< Minimum alpha value to be drawn, otherwise fragment will be discarded. */

uniform bool		u_cc3FogIsEnabled;			/**< Whether scene fogging is enabled. */
uniform lowp vec4	u_cc3FogColor;				/**< Fog color. */
uniform int			u_cc3FogAttenuationMode;	/**< Fog attenuation mode (one of GL_LINEAR, GL_EXP or GL_EXP2). */
uniform highp float	u_cc3FogDensity;			/**< Fog density. */
uniform highp float	u_cc3FogStartDistance;		/**< Distance from camera at which fogging effect starts. */
uniform highp float	u_cc3FogEndDistance;		/**< Distance from camera at which fogging effect ends. */

uniform int			u_cc3TextureCount;									/**< Number of textures. */
uniform sampler2D	s_cc3Textures[MAX_TEXTURES];						/**< Texture samplers. */
uniform lowp vec4	u_cc3TextureUnitColor[MAX_TEXTURES];				/**< Constant color of this texure unit (often used for normal mapping). */
uniform int			u_cc3TextureUnitMode[MAX_TEXTURES];					/**< Texture environment mode for this texture unit. */
uniform int			u_cc3TextureUnitCombineRGBFunction[MAX_TEXTURES];	/**< RGB combiner function for this texture unit. */
uniform int			u_cc3TextureUnitRGBSource0[MAX_TEXTURES];			/**< The source of the RGB components for arg0 of the combiner function in this texture unit. */
uniform int			u_cc3TextureUnitRGBSource1[MAX_TEXTURES];			/**< The source of the RGB components for arg1 of the combiner function in this texture unit. */
uniform int			u_cc3TextureUnitCombineAlphaFunction[MAX_TEXTURES];	/**< Alpha combiner function for this texture unit. */
uniform int			u_cc3TextureUnitAlphaSource0[MAX_TEXTURES];			/**< The source of the alpha components for arg0 of the combiner function in this texture unit. */
uniform int			u_cc3TextureUnitAlphaSource1[MAX_TEXTURES];			/**< The source of the alpha components for arg1 of the combiner function in this texture unit. */

//-------------- VARYING VARIABLE INPUTS ----------------------
varying vec2		v_texCoord[MAX_TEXTURES];	/**< Fragment texture coordinates. */
varying lowp vec4	v_color;					/**< Fragment front-face color. */
varying lowp vec4	v_colorBack;				/**< Fragment back-face color. */
varying highp float	v_distEye;					/**< Fragment distance in eye coordinates. */
varying vec3		v_bumpMapLightDir;			/**< Direction to the first light in tangent space. */

//-------------- LOCAL VARIABLES ----------------------
lowp vec4 fragColor;
lowp vec4 primaryColor;

//-------------- FUNCTIONS ----------------------

/**
 * Provide texture combining functionality similar to OpenGL ES 1.1, to combine the texel
 * from the specified texture unit with the existing fragment color.
 *
 * This function is called from applyTexture when the texture unit mode is set to GL_COMBINE.
 *
 * The implementation of this function is a simplification of some of the OpenGL ES 1.1
 * configuration options. It only uses two source channels (and therefore does not support
 * the triple-source GL_INTERPOLATE function), and assumes that all source operands reference
 * the source component directly (ie- no (1 - src)).
 */
void combineTexture(lowp vec4 texColor, int tuIdx) {
	int func, src0, src1;
	lowp vec3 rgb0, rgb1;
	lowp float a0, a1;
	
	// Extract the RGB components from the appropriate sources
	func = u_cc3TextureUnitCombineRGBFunction[tuIdx];
	src0 = u_cc3TextureUnitRGBSource0[tuIdx];
	src1 = u_cc3TextureUnitRGBSource1[tuIdx];

	// RGB of source 0, starting with default
	if (src0 == k_GL_TEXTURE)				rgb0 = texColor.rgb;
	else if (src0 == k_GL_PREVIOUS)			rgb0 = fragColor.rgb;
	else if (src0 == k_GL_CONSTANT)			rgb0 = u_cc3TextureUnitColor[tuIdx].rgb;
	else if (src0 == k_GL_PRIMARY_COLOR)	rgb0 = primaryColor.rgb;
	
	// RGB of source 1, starting with default
	if (src1 == k_GL_PREVIOUS)				rgb1 = fragColor.rgb;
	else if (src1 == k_GL_TEXTURE)			rgb1 = texColor.rgb;
	else if (src1 == k_GL_CONSTANT)			rgb1 = u_cc3TextureUnitColor[tuIdx].rgb;
	else if (src1 == k_GL_PRIMARY_COLOR)	rgb1 = primaryColor.rgb;
	
	// Combine the RGB components
	if (func == k_GL_MODULATE)			fragColor.rgb = rgb0 * rgb1;
	else if (func == k_GL_ADD)			fragColor.rgb = rgb0 + rgb1;
	else if (func == k_GL_ADD_SIGNED)	fragColor.rgb = rgb0 + rgb1 - 0.5;
	else if (func == k_GL_SUBTRACT)		fragColor.rgb = rgb0 - rgb1;
	else if (func == k_GL_REPLACE)		fragColor.rgb = rgb0;
	else if (func == k_GL_DOT3_RGBA) {
		if (u_cc3VertexHasTangent)		// Bump-map using tangent-space light dir
			fragColor = lowp vec4(2.0 * dot(rgb0 - 0.5, v_bumpMapLightDir));
		else							// Bump-map using model-space light dir (from const color)
			fragColor = lowp vec4(4.0 * dot(rgb0 - 0.5, rgb1 - 0.5));
	}
	else if (func == k_GL_DOT3_RGB) {
		if (u_cc3VertexHasTangent)		// Bump-map using tangent-space light dir
			fragColor.rgb = lowp vec3(2.0 * dot(rgb0 - 0.5, v_bumpMapLightDir));
		else							// Bump-map using model-space light dir (from const color)
			fragColor.rgb = lowp vec3(4.0 * dot(rgb0 - 0.5, rgb1 - 0.5));
	}
	
	// Extract the alpha components from the appropriate sources
	func = u_cc3TextureUnitCombineAlphaFunction[tuIdx];
	src0 = u_cc3TextureUnitAlphaSource0[tuIdx];
	src1 = u_cc3TextureUnitAlphaSource1[tuIdx];
	
	// Alpha of source 0, starting with default
	if (src0 == k_GL_TEXTURE)				a0 = texColor.a;
	else if (src0 == k_GL_PREVIOUS)			a0 = fragColor.a;
	else if (src0 == k_GL_CONSTANT)			a0 = u_cc3TextureUnitColor[tuIdx].a;
	else if (src0 == k_GL_PRIMARY_COLOR)	a0 = primaryColor.a;
	
	// Alpha of source 1, starting with default
	if (src1 == k_GL_PREVIOUS)				a1 = fragColor.a;
	else if (src1 == k_GL_TEXTURE)			a1 = texColor.a;
	else if (src1 == k_GL_CONSTANT)			a1 = u_cc3TextureUnitColor[tuIdx].a;
	else if (src1 == k_GL_PRIMARY_COLOR)	a1 = primaryColor.a;
	
	// Combine the alpha components
	if (func == k_GL_MODULATE)			fragColor.a = a0 * a1;
	else if (func == k_GL_ADD)			fragColor.a = a0 + a1;
	else if (func == k_GL_ADD_SIGNED)	fragColor.a = a0 + a1 - 0.5;
	else if (func == k_GL_SUBTRACT)		fragColor.a = a0 - a1;
	else if (func == k_GL_REPLACE)		fragColor.a = a0;
}

/**
 * Applies the texture assigned to the specified texture unit index, combining it with
 * the fragment color already applied as defined by the texture unit parameters.
 */
void applyTexture(int tuIdx) {
	lowp vec4 texColor = texture2D(s_cc3Textures[tuIdx], v_texCoord[tuIdx]);
	int tuMode = u_cc3TextureUnitMode[tuIdx];
	
	if (tuMode == k_GL_COMBINE)
		combineTexture(texColor, tuIdx);
	else if (tuMode == k_GL_MODULATE)
		fragColor *= texColor;
	else if (tuMode == k_GL_DECAL)
		fragColor.rgb = (texColor.rgb * texColor.a) + (fragColor.rgb * (1.0 - texColor.a));
	else if (tuMode == k_GL_REPLACE)
		fragColor = texColor;
	else if (tuMode == k_GL_ADD) {
		fragColor.rgb += texColor.rgb;
		fragColor.a *= texColor.a;
	}
	else if (tuMode == k_GL_BLEND) {
		fragColor.rgb =  (fragColor.rgb * (1.0 - texColor.rgb)) + (u_cc3TextureUnitColor[tuIdx].rgb * texColor.rgb);
		fragColor.a *= texColor.a;
	}
}

/**
 * Applies any textures to the fragment, combining them as defined by the texture units,
 * and returns the resulting fragment color. If there are no textures, returns the fragment
 * color from the v_color varying input variable.
 */
#if (CC3_PLATFORM_IOS || CC3_PLATFORM_OSX)
void applyTextures() {
	// iOS doesn't handle the unrolled loop (required by Android) well here, so loop it
	for (int tuIdx = 0; tuIdx < MAX_TEXTURES; tuIdx++) {
		if (tuIdx == u_cc3TextureCount) return;		// Break out once we've applied all the textures
		applyTexture(tuIdx);
	}
}
#endif	// (CC3_PLATFORM_IOS || CC3_PLATFORM_OSX)

#if CC3_PLATFORM_ANDROID
void applyTextures() {
	// Android doesn't handle looping well here...so we unroll it
	if (u_cc3TextureCount <= 0) return;
	applyTexture(0);
	if (u_cc3TextureCount <= 1) return;
	applyTexture(1);
//	if (u_cc3TextureCount <= 2) return;		// Uncomment to match MAX_TEXTURES
//	applyTexture(2);
//	if (u_cc3TextureCount <= 3) return;
//	applyTexture(3);
}
#endif	// CC3_PLATFORM_ANDROID

/** Applies fog to the specified color and returns the adjusted color. */
lowp vec4 fogify(lowp vec4 aColor) {
	
#	define k_GL_LINEAR                 0x2601
#	define k_GL_EXP                    0x0800
#	define k_GL_EXP2                   0x0801
	
	if ( !u_cc3FogIsEnabled ) return aColor;
	
	// Determine visibility based on fog attentuation characteristics and distance through fog
	float visibility = 1.0;
	if (u_cc3FogAttenuationMode == k_GL_LINEAR) {
		visibility = (u_cc3FogEndDistance - v_distEye) / (u_cc3FogEndDistance - u_cc3FogStartDistance);
	} else if (u_cc3FogAttenuationMode == k_GL_EXP) {
		float d = u_cc3FogDensity * v_distEye;
		visibility = exp(-d);
	} else if (u_cc3FogAttenuationMode == k_GL_EXP2) {
		float d = u_cc3FogDensity * v_distEye;
		visibility = exp(-(d * d));
	}
	visibility = clamp(visibility, 0.0, 1.0);
	
	// Mix alpha-adjusted fog color into fragment color based on visibility.
	aColor.rgb = mix(u_cc3FogColor.rgb * aColor.a, aColor.rgb, visibility);
	return aColor;
}

//-------------- ENTRY POINT ----------------------

void main() {
	primaryColor = gl_FrontFacing ? v_color : v_colorBack;
	fragColor = primaryColor;
	applyTextures();

	// If the fragment passes the alpha test, fog it and draw it, otherwise discard
	if (fragColor.a >= u_cc3MaterialMinimumDrawnAlpha)
		gl_FragColor = fogify(fragColor);
	else
		discard;
}

// ------------- ALTERNATE PERFORMANCE TESTING FUNCTIONS --------------

/**
 * This is a dummy alternate to the applyTextures function. It deliberately applies zero textures.
 * By pretending to make use of the applyTexture() function, all of the uniforms remain active,
 * allowing the testing of the CPU overhead when setting large numbers of uniforms.
 */
//void applyNoTextures() { for (int tuIdx = 0; tuIdx < 0; tuIdx++) applyTexture(tuIdx); }

/**
 * Alternate main function that deliberately applies no textures and directly assigns the 
 * fragment color from the varying variable. Uncomment the applyNoTextures function to fool
 * the compiler into thinking that textures will be applied, thereby causing the compiler 
 * to keep all of the uniforms active. This permits analysis of the overhead on the CPU of 
 * a large number of uniforms. To see the effect, comment out the normal main function and
 * uncomment this version. For even better performance, comment out the call to applyNoTextures
 * below, to avoid the binding of the additional uniforms.
 */
//void main() {
//	applyNoTextures();
//	gl_FragColor = v_color;
//}
