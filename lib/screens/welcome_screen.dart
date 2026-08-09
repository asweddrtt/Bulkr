import 'package:bulkr/go_router/app_routes.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../widgets/outlined_button.dart';
import '../widgets/welcome_button.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/background.png'),
            fit: BoxFit.cover,
          ),
        ),
        padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 40.h),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
                
              // --- 1. HEADER SECTION ---
              Text(
                'welcome_time_to'.tr(),
                style: GoogleFonts.anton(
                  fontSize: 72.sp,
                  fontWeight: FontWeight.normal,
                  height: 0.9,
                  letterSpacing: -2,
                  color: Colors.white,
                ),
              ),
              Text(
                'welcome_grow'.tr(),
                style: GoogleFonts.anton(
                  fontSize: 72.sp,
                  fontWeight: FontWeight.normal,
                  height: 0.9,
                  letterSpacing: -2,
                  color: const Color(0xFFC3F400), // The neon color
                ),
              ),
              SizedBox(height: 23.h),
              Text(
                'welcome_subtitle'.tr(),
                style: GoogleFonts.inter(
                  fontSize: 18.sp,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFFC4C9AC),
                ),
              ),
              SizedBox(height: 40.h),
                
              // --- 2. BUTTONS SECTION ---
                
              PrimaryIconButton(
                label: 'continue_apple'.tr(),
                icon: Icons.apple,
                onPressed: () {},
              ),
              SizedBox(height: 16.h),
                
                // Google Button
              PrimaryIconButton(
                label: 'continue_google'.tr(),
                customIcon: Image.asset("assets/images/google.png", height: 28.sp),
                onPressed: () {
                  context.push(AppRoutes.baseline);
                },
              ),
              SizedBox(height: 16.h),
                
                // Other Options Button
              SecondaryOutlinedButton(
                label: 'other_options'.tr(),
                onPressed: () {},
              ),
              SizedBox(height: 40.h),
                
              // --- 3. FOOTER SECTION ---
              RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  style: GoogleFonts.anton(
                    fontSize: 11.sp,
                    color: const Color(0xFF888888),
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.w600,
                  ),
                  children: [
                    TextSpan(text: 'agree_prefix'.tr(),
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 11.sp,
                        fontWeight: FontWeight.bold,
                        color: Color(0xffC4C9AC),
                      ),
                    ),
                    TextSpan(
                      text: 'policy'.tr(),
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 11.sp,
                        fontWeight: FontWeight.bold,
                        color: Color(0xffC4C9AC),
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}